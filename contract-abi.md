# Trust BTP — Référence ABI des contrats

> Liste exhaustive de toutes les fonctions publiques de chaque contrat.
> Document de référence pour l'intégration frontend.
> Source : code Solidity compilé avec Hardhat.

---

## Types partagés (`DataTypes.sol`)

### Enum `ChantierStatus`

| Valeur | Index |
|---|---|
| `DevisSubmitted` | 0 |
| `DevisRejected` | 1 |
| `Active` | 2 |
| `Paused` | 3 |
| `InLitige` | 4 |
| `Completed` | 5 |
| `Cancelled` | 6 |

### Enum `JalonStatus`

| Valeur | Index |
|---|---|
| `Pending` | 0 |
| `Finished` | 1 |
| `Accepted` | 2 |
| `AcceptedWithReserves` | 3 |
| `PaidWithReserves` | 4 |
| `InLitige` | 5 |
| `ReservesLifted` | 6 |

### Struct `Chantier`

```solidity
struct Chantier {
    uint256 id;
    address artisan;
    address particulier;
    address token;          // USDC
    uint256 devisAmount;    // montant total du devis (6 décimales)
    uint256 depositAmount;  // 110% du devis (6 décimales)
    bool    yieldOptIn;     // true = fonds déposés dans Aave
    ChantierStatus status;
    uint8   currentJalonIndex;
    uint8   jalonCount;     // 1 à 5
    uint256 submittedAt;    // timestamp
    uint256 acceptedAt;     // timestamp (0 si pas encore accepté)
    uint256 completedAt;    // timestamp (0 si pas terminé)
}
```

### Struct `Jalon`

```solidity
struct Jalon {
    string  description;         // immuable
    uint256 amount;              // montant brut (6 décimales)
    JalonStatus status;
    uint256 finishedAt;          // timestamp validateJalon
    bytes32 artisanProofHash;    // keccak256 ou CID IPFS
    bytes32 clientProofHash;     // preuve du particulier (réserves)
    uint256 blockedAmount;       // montant retenu (réserves mineures/majeures)
    uint256 penaltyAmount;       // pénalité 3% (réserves mineures)
}
```

### Constantes

```solidity
MAX_JALONS               = 5
BPS_DENOMINATOR          = 10_000
DEPOSIT_RATIO_BPS        = 11_000   // 110%
PLATFORM_FEE_BPS         = 200      // 2%
MINOR_RESERVE_BLOCK_BPS  = 1_000    // 10%
MINOR_RESERVE_PENALTY_BPS= 300      // 3%
AUTO_VALIDATE_DELAY      = 48 heures
```

---

## Contrat `EscrowVault`

Adresse : à récupérer dans `ignition/deployments/chain-<chainId>/deployed_addresses.json`

### Variables publiques (lecture directe)

| Variable | Type | Description |
|---|---|---|
| `trustScoreRegistry` | `address` | Adresse du contrat TrustScoreRegistry |
| `yieldProvider` | `address` | Adresse du provider DeFi actif (ou 0x0) |
| `chantierNFT` | `address` | Adresse du contrat ChantierNFT |
| `arbiter` | `address` | Adresse de l'arbitre actuel |
| `treasury` | `address` | Adresse de la trésorerie |
| `allowedTokens(address)` | `bool` | true si le token est autorisé (USDC) |
| `chantiers(uint256)` | `Chantier` | Données d'un chantier par son ID |
| `jalons(uint256, uint8)` | `Jalon` | Données d'un jalon (chantierId, index) |
| `platformFees(address)` | `uint256` | Frais accumulés par token (non collectés) |
| `yieldPrincipal(address)` | `uint256` | Principal déposé dans Aave par token |

---

### Fonctions d'écriture — Artisan

---

#### `submitDevis`

```solidity
function submitDevis(
    address particulier,
    address token,
    uint256 devisAmount,
    string[] calldata jalonDescriptions,
    uint256[] calldata jalonAmounts
) external returns (uint256 chantierId)
```

**Description** : L'artisan soumet un devis à un particulier. Crée le chantier en statut `DevisSubmitted`. Le devis est figé dès la soumission — descriptions et montants sont immuables.

**Paramètres** :

| Nom | Type | Description |
|---|---|---|
| `particulier` | `address` | Adresse du client |
| `token` | `address` | Token de paiement (doit être autorisé — USDC) |
| `devisAmount` | `uint256` | Montant total du devis (6 décimales USDC) |
| `jalonDescriptions` | `string[]` | Descriptions des jalons (1 à 5 éléments) |
| `jalonAmounts` | `uint256[]` | Montants des jalons (somme = devisAmount) |

**Retour** : `chantierId` — identifiant unique du chantier créé (uint256, commence à 0).

**Contraintes** :
- `token` doit être dans `allowedTokens`
- `particulier != address(0)`
- `1 <= jalonDescriptions.length <= 5`
- `sum(jalonAmounts) == devisAmount`

**Événement émis** : `DevisSoumis(chantierId, artisan, particulier, token, devisAmount)`

---

#### `validateJalon`

```solidity
function validateJalon(
    uint256 chantierId,
    bytes32 proofHash
) external
```

**Description** : L'artisan déclare le jalon courant terminé et soumet sa preuve. Passe le jalon de `Pending` à `Finished`. Démarre le délai de 48h pendant lequel le particulier peut lever des réserves.

**Paramètres** :

| Nom | Type | Description |
|---|---|---|
| `chantierId` | `uint256` | Identifiant du chantier |
| `proofHash` | `bytes32` | Hash keccak256 ou CID IPFS de la preuve artisan |

**Contraintes** :
- `msg.sender == chantiers[chantierId].artisan`
- Statut chantier : `Active`
- Statut jalon courant : `Pending`

**Événement émis** : `JalonValide(chantierId, jalonIndex, proofHash)`

---

#### `acknowledgeReserves`

```solidity
function acknowledgeReserves(
    uint256 chantierId,
    bool accept
) external
```

**Description** : L'artisan répond aux réserves mineures posées par le particulier.
- `accept = true` : accepte les déductions (10% bloqué + 3% pénalité), reçoit un paiement partiel immédiat (87%).
- `accept = false` : refuse les déductions, ouvre un litige. Le score artisan est gelé.

**Paramètres** :

| Nom | Type | Description |
|---|---|---|
| `chantierId` | `uint256` | Identifiant du chantier |
| `accept` | `bool` | true = accepte les réserves, false = ouvre un litige |

**Contraintes** :
- `msg.sender == chantiers[chantierId].artisan`
- Statut chantier : `Active`
- Statut jalon courant : `AcceptedWithReserves`

**Événements émis** :
- Si `accept = true` : `ReservesAccusees(chantierId, jalonIndex, montantPaye)`
- Si `accept = false` : `LitigeOuvert(chantierId, jalonIndex)`

---

### Fonctions d'écriture — Particulier

---

#### `rejectDevis`

```solidity
function rejectDevis(uint256 chantierId) external
```

**Description** : Le particulier refuse le devis. Le chantier est définitivement clôturé en statut `DevisRejected`. Aucun fonds n'est transféré (aucun dépôt n'a eu lieu). Pour un nouveau devis, l'artisan doit créer un nouveau chantier.

**Paramètres** :

| Nom | Type | Description |
|---|---|---|
| `chantierId` | `uint256` | Identifiant du chantier |

**Contraintes** :
- `msg.sender == chantiers[chantierId].particulier`
- Statut chantier : `DevisSubmitted`

**Événement émis** : `DevisRefuse(chantierId, particulier)`

---

#### `acceptDevis`

```solidity
function acceptDevis(
    uint256 chantierId,
    bool yieldOptIn
) external
```

**Description** : Le particulier signe le devis ET dépose 110% du montant en USDC en une transaction. Le chantier passe en statut `Active`. Un NFT soulbound (tokenId = chantierId) est minté et détenu par le vault.

**Prérequis** : Le particulier doit avoir préalablement approuvé le vault pour le montant `depositAmount = devisAmount * 110%` via `IERC20(usdc).approve(escrowVault, depositAmount)`.

**Paramètres** :

| Nom | Type | Description |
|---|---|---|
| `chantierId` | `uint256` | Identifiant du chantier |
| `yieldOptIn` | `bool` | true = les fonds sont déposés dans Aave V3 pour générer du yield |

**Contraintes** :
- `msg.sender == chantiers[chantierId].particulier`
- Statut chantier : `DevisSubmitted`
- Approbation ERC-20 préalable pour `depositAmount`

**Événement émis** : `DevisAccepte(chantierId, particulier, depositAmount, yieldOptIn)`

---

#### `acceptJalon`

```solidity
function acceptJalon(uint256 chantierId) external
```

**Description** : Le particulier valide explicitement le jalon courant sans réserve, avant l'expiration du délai 48h. Libère 98% du montant brut à l'artisan (2% = commission plateforme). Passe au jalon suivant ou clôture le chantier si c'était le dernier.

**Paramètres** :

| Nom | Type | Description |
|---|---|---|
| `chantierId` | `uint256` | Identifiant du chantier |

**Contraintes** :
- `msg.sender == chantiers[chantierId].particulier`
- Statut chantier : `Active`
- Statut jalon courant : `Finished`

**Événement émis** : `JalonAccepte(chantierId, jalonIndex, montantLibere)`

---

#### `acceptJalonWithMinorReserves`

```solidity
function acceptJalonWithMinorReserves(
    uint256 chantierId,
    bytes32 clientProofHash
) external
```

**Description** : Le particulier accepte le jalon avec des réserves mineures. 10% du montant du jalon est bloqué en attente de correction. 3% de pénalité est prélevé immédiatement sur l'artisan (versé à la plateforme). L'artisan doit ensuite appeler `acknowledgeReserves()`.

**Calcul** :
```
blockedAmount  = jalon.amount × 10%
penaltyAmount  = jalon.amount × 3%
paiementArtisan = jalon.amount × 87% (après acknowledgeReserves(true))
```

**Paramètres** :

| Nom | Type | Description |
|---|---|---|
| `chantierId` | `uint256` | Identifiant du chantier |
| `clientProofHash` | `bytes32` | Hash keccak256 de la preuve de non-conformité (photos, doc) |

**Contraintes** :
- `msg.sender == chantiers[chantierId].particulier`
- Statut chantier : `Active`
- Statut jalon courant : `Finished`

**Événement émis** : `JalonAccepteAvecReserves(chantierId, jalonIndex, false, clientProofHash)`

---

#### `acceptJalonWithMajorReserves`

```solidity
function acceptJalonWithMajorReserves(
    uint256 chantierId,
    bytes32 clientProofHash
) external
```

**Description** : Le particulier signale des réserves MAJEURES. Le chantier est suspendu (statut `Paused`). Aucun paiement n'est effectué. Le jalon entier est bloqué jusqu'à reprise. Reprise via `resumeChantier()` (particulier ou arbitre).

**Paramètres** :

| Nom | Type | Description |
|---|---|---|
| `chantierId` | `uint256` | Identifiant du chantier |
| `clientProofHash` | `bytes32` | Hash keccak256 de la preuve de non-conformité |

**Contraintes** :
- `msg.sender == chantiers[chantierId].particulier`
- Statut chantier : `Active`
- Statut jalon courant : `Finished`

**Événements émis** :
- `JalonAccepteAvecReserves(chantierId, jalonIndex, true, clientProofHash)`
- `ChantierEnPause(chantierId, jalonIndex)`

---

#### `lifterReserves`

```solidity
function lifterReserves(uint256 chantierId) external
```

**Description** : Le particulier confirme que l'artisan a corrigé les points soulevés lors des réserves mineures. La part bloquée (10%) est libérée à l'artisan. On passe ensuite au jalon suivant ou on clôture si c'était le dernier.

**Paramètres** :

| Nom | Type | Description |
|---|---|---|
| `chantierId` | `uint256` | Identifiant du chantier |

**Contraintes** :
- `msg.sender == chantiers[chantierId].particulier`
- Statut chantier : `Active`
- Statut jalon courant : `PaidWithReserves`

**Événement émis** : `ReservesLevees(chantierId, jalonIndex, montantDebloque)`

---

#### `resumeChantier`

```solidity
function resumeChantier(uint256 chantierId) external
```

**Description** : Reprend le chantier suspendu suite à des réserves majeures. Le jalon courant est remis en statut `Pending` pour que l'artisan puisse resoumettre sa preuve. Peut être appelé par le particulier ou l'arbitre.

**Paramètres** :

| Nom | Type | Description |
|---|---|---|
| `chantierId` | `uint256` | Identifiant du chantier |

**Contraintes** :
- `msg.sender == particulier || msg.sender == arbiter`
- Statut chantier : `Paused`

**Événement émis** : `ChantierRepris(chantierId, jalonIndex)`

---

#### `cancelChantier`

```solidity
function cancelChantier(uint256 chantierId) external
```

**Description** : Le particulier annule le chantier avant que l'artisan n'ait démarré le premier jalon. L'artisan reçoit le montant du 1er jalon en compensation. Le particulier récupère le reste.

**Calcul** :
```
artisan reçoit    : jalons[0].amount
particulier reçoit: depositAmount − jalons[0].amount
```

**Paramètres** :

| Nom | Type | Description |
|---|---|---|
| `chantierId` | `uint256` | Identifiant du chantier |

**Contraintes** :
- `msg.sender == chantiers[chantierId].particulier`
- Statut chantier : `Active`
- `currentJalonIndex == 0` et jalon 0 en `Pending` (pas encore démarré)

**Événement émis** : `ChantierAnnule(chantierId)`

---

### Fonctions d'écriture — N'importe qui

---

#### `triggerAutoValidation`

```solidity
function triggerAutoValidation(uint256 chantierId) external
```

**Description** : Déclenche la validation automatique du jalon courant si 48 heures se sont écoulées depuis `validateJalon()` sans réaction du particulier. Appelable par n'importe quelle adresse. Libère les fonds à l'artisan comme une validation normale.

**Paramètres** :

| Nom | Type | Description |
|---|---|---|
| `chantierId` | `uint256` | Identifiant du chantier |

**Contraintes** :
- Statut chantier : `Active`
- Statut jalon courant : `Finished`
- `block.timestamp >= jalon.finishedAt + 48 heures`

**Événements émis** :
- `JalonAutoValide(chantierId, jalonIndex)`
- `JalonAccepte(chantierId, jalonIndex, montantLibere)`

---

### Fonctions d'écriture — Arbitre

---

#### `resolveLitige`

```solidity
function resolveLitige(
    uint256 chantierId,
    bool artisanEnTort,
    uint256 blockedBps,
    uint256 penaltyBps
) external
```

**Description** : L'arbitre tranche le litige et définit la répartition des fonds du jalon concerné. Le chantier reprend après résolution. Le score artisan est dégel et mis à jour (−15 pts litige).

**Calcul selon la décision** :

Si `artisanEnTort = true` :
```
particulier reçoit : jalon − blockedBps% − penaltyBps%
plateforme garde   : blockedBps% + penaltyBps%
```

Si `artisanEnTort = false` :
```
artisan reçoit     : jalon − blockedBps% − penaltyBps%
plateforme garde   : blockedBps% + penaltyBps%
```

**Paramètres** :

| Nom | Type | Description |
|---|---|---|
| `chantierId` | `uint256` | Identifiant du chantier en litige |
| `artisanEnTort` | `bool` | true = artisan responsable, false = particulier |
| `blockedBps` | `uint256` | BPS du montant conservé par la plateforme (0–10 000) |
| `penaltyBps` | `uint256` | BPS de pénalité supplémentaire (0–5 000) |

**Contraintes** :
- `msg.sender == arbiter`
- Statut chantier : `InLitige`
- `blockedBps <= 10_000`
- `penaltyBps <= 5_000`

**Événement émis** : `LitigeResolu(chantierId, jalonIndex, artisanEnTort, montantArtisan, remboursementParticulier, penalitePlateforme)`

---

### Fonctions d'écriture — Owner

---

#### `setAllowedToken`

```solidity
function setAllowedToken(address token, bool autorise) external
```

**Description** : Autorise ou révoque un token ERC-20 comme moyen de paiement accepté sur la plateforme.

| Nom | Type | Description |
|---|---|---|
| `token` | `address` | Adresse du token ERC-20 |
| `autorise` | `bool` | true = autorisé, false = révoqué |

---

#### `setYieldProvider`

```solidity
function setYieldProvider(address nouveau) external
```

**Description** : Met à jour l'adresse du provider de yield DeFi (ex: migration Aave → Morpho). L'ancien provider n'est pas automatiquement vidé.

| Nom | Type | Description |
|---|---|---|
| `nouveau` | `address` | Adresse du nouveau contrat IYieldProvider |

**Événement émis** : `YieldProviderMisAJour(ancien, nouveau)`

---

#### `setArbiter`

```solidity
function setArbiter(address nouvelArbiter) external
```

**Description** : Change l'adresse de l'arbitre autorisé à résoudre les litiges.

| Nom | Type | Description |
|---|---|---|
| `nouvelArbiter` | `address` | Nouvelle adresse arbitre (non-zéro) |

**Événement émis** : `ArbiterMisAJour(ancien, nouveau)`

---

#### `collecterFrais`

```solidity
function collecterFrais(address token) external
```

**Description** : Transfère tous les frais plateforme accumulés (2% par jalon + pénalités) vers la trésorerie. Réinitialise le compteur `platformFees[token]`.

| Nom | Type | Description |
|---|---|---|
| `token` | `address` | Token à collecter (USDC) |

**Événement émis** : `FraisCollectes(token, montant)`

---

#### `collecterYield`

```solidity
function collecterYield(address token) external
```

**Description** : Collecte le yield généré par le provider DeFi (différence entre valeur totale des aTokens et principal déposé). Transfère le yield vers la trésorerie.

| Nom | Type | Description |
|---|---|---|
| `token` | `address` | Token à collecter (USDC) |

**Événement émis** : `YieldCollecte(token, montant)`

---

### Fonctions de lecture (view)

---

#### `getCurrentJalon`

```solidity
function getCurrentJalon(uint256 chantierId) external view returns (Jalon memory)
```

Retourne le jalon actuellement en cours (`jalons[chantierId][currentJalonIndex]`).

---

#### `getJalon`

```solidity
function getJalon(uint256 chantierId, uint8 jalonIndex) external view returns (Jalon memory)
```

Retourne un jalon spécifique par son index (0 à jalonCount−1).

---

#### `getAllJalons`

```solidity
function getAllJalons(uint256 chantierId) external view returns (Jalon[] memory)
```

Retourne le tableau complet de tous les jalons d'un chantier.

---

### Erreurs personnalisées

| Erreur | Déclencheur |
|---|---|
| `TokenNonAutorise(token)` | Token non dans `allowedTokens` |
| `NombreJalonsInvalide(count)` | Moins de 1 ou plus de 5 jalons |
| `SommeJalonsMismatch(somme, devis)` | Somme des jalons ≠ devisAmount |
| `PasLeParticulier(chantierId)` | msg.sender ≠ particulier du chantier |
| `PasLArtisan(chantierId)` | msg.sender ≠ artisan du chantier |
| `PasLArbiter()` | msg.sender ≠ arbiter |
| `StatutChantierIncorrect(attendu, actuel)` | Mauvais statut de chantier |
| `StatutJalonIncorrect(attendu, actuel)` | Mauvais statut de jalon |
| `AutoValidationPasPrete(disponibleAt, maintenant)` | Délai 48h pas encore écoulé |
| `AdresseZero()` | Adresse nulle fournie |
| `BpsInvalide(bps)` | BPS hors bornes autorisées |

---

## Contrat `ChantierNFT`

### Struct `DevisData`

```solidity
struct DevisData {
    uint256 chantierId;
    address artisan;
    address particulier;
    address token;
    uint256 devisAmount;
    uint256 depositAmount;
    uint8   jalonCount;
    uint256 submittedAt;
    uint256 acceptedAt;
}
```

### Fonctions de lecture (view)

---

#### `getDevisData`

```solidity
function getDevisData(uint256 chantierId) external view returns (DevisData memory)
```

Retourne toutes les données immuables du chantier stockées dans le NFT.

---

#### `getJalonStatuses`

```solidity
function getJalonStatuses(uint256 chantierId) external view returns (JalonStatus[] memory)
```

Retourne le tableau de tous les statuts de jalons (mutables). Mis à jour automatiquement par le vault à chaque transition.

---

#### `getJalonStatus`

```solidity
function getJalonStatus(uint256 chantierId, uint8 jalonIndex) external view returns (JalonStatus)
```

Retourne le statut d'un jalon spécifique.

---

#### `tokenURI`

```solidity
function tokenURI(uint256 tokenId) public view returns (string memory)
```

Retourne les métadonnées JSON complètes encodées en base64 (`data:application/json;base64,...`). Contient : identifiants, adresses, montants, nombre de jalons, tableau des jalons avec descriptions et statuts.

---

#### `ownerOf` (ERC-721)

```solidity
function ownerOf(uint256 tokenId) public view returns (address)
```

Retourne l'adresse du vault (seul détenteur — NFT soulbound).

---

### Fonctions d'écriture (vault uniquement)

Ces fonctions ne sont pas appelées directement par le frontend.

| Fonction | Description |
|---|---|
| `mintChantier(...)` | Minte le NFT lors de `acceptDevis()` |
| `updateJalonStatus(chantierId, jalonIndex, newStatus)` | Synchronise le statut d'un jalon |

### Erreurs

| Erreur | Déclencheur |
|---|---|
| `Soulbound()` | Tentative de transfert du NFT |
| `ChantierDejaTokenise(chantierId)` | NFT déjà minté pour ce chantierId |
| `JalonIndexInvalide(index, count)` | Index hors limites |

### Événements

| Événement | Paramètres |
|---|---|
| `ChantierMinte(chantierId, vault)` | Lors du mint |
| `JalonStatusMisAJour(chantierId, jalonIndex, newStatus)` | À chaque changement de statut |

---

## Contrat `TrustScoreRegistry`

### Enum `Tier` (ITrustScoreRegistry)

| Valeur | Index | Score |
|---|---|---|
| `Nouveau` | 0 | 0–39 |
| `Confirme` | 1 | 40–64 |
| `Expert` | 2 | 65–84 |
| `Elite` | 3 | 85–100 |

### Fonctions de lecture (view)

---

#### `getScore`

```solidity
function getScore(address artisan) external view returns (uint256)
```

Retourne le score de réputation de l'artisan (0–100). Retourne 50 (score initial) pour les artisans inconnus.

---

#### `getTier`

```solidity
function getTier(address artisan) external view returns (Tier)
```

Retourne le tier de réputation dérivé du score : `Nouveau`, `Confirme`, `Expert` ou `Elite`.

---

#### `getStats`

```solidity
function getStats(address artisan) external view returns (
    uint256 score,
    Tier tier,
    uint256 chantiersCompleted,
    uint256 litigesCount,
    bool frozen
)
```

Retourne les statistiques complètes d'un artisan en une seule lecture.

| Retour | Type | Description |
|---|---|---|
| `score` | `uint256` | Score actuel (0–100) |
| `tier` | `Tier` | Tier de réputation |
| `chantiersCompleted` | `uint256` | Nombre total de chantiers terminés |
| `litigesCount` | `uint256` | Nombre total de litiges subis |
| `frozen` | `bool` | true = score gelé (litige en cours) |

---

### Variables publiques

| Variable | Type | Description |
|---|---|---|
| `escrowVault` | `address` | Adresse du vault autorisé à modifier les scores |

---

### Événements

| Événement | Paramètres | Déclencheur |
|---|---|---|
| `ScoreUpdated(artisan, oldScore, newScore, newTier)` | Après chaque chantier terminé | `updateScore()` |
| `ScoreFrozen(artisan, chantierId)` | Litige ouvert | `freezeScore()` |
| `ScoreUnfrozen(artisan, chantierId)` | Litige résolu | `unfreezeScore()` |

---

## Contrat `AaveV3YieldProvider`

### Fonctions de lecture (view)

---

#### `totalValue`

```solidity
function totalValue(address token) external view returns (uint256)
```

Retourne la valeur totale des aTokens détenus (capital + yield accumulé).

---

#### `pendingYield`

```solidity
function pendingYield(address token, uint256 depositedPrincipal) external view returns (uint256)
```

Retourne le yield disponible = `totalValue(token) − depositedPrincipal`.

| Paramètre | Type | Description |
|---|---|---|
| `token` | `address` | Token concerné (USDC) |
| `depositedPrincipal` | `uint256` | Capital total déposé (utiliser `yieldPrincipal[token]` du vault) |

---

#### `providerName`

```solidity
function providerName() external pure returns (string memory)
```

Retourne `"Aave V3"`.

---

## Notes d'intégration frontend

### Lecture de tous les chantiers d'un utilisateur

Le contrat n'expose pas de mapping par adresse. Pour récupérer les chantiers d'un utilisateur :

1. **Filtrer les événements** `DevisSoumis` (artisan) et `DevisAccepte` (particulier) depuis le début du déploiement.
2. **Ou** maintenir un index off-chain / subgraph qui indexe les événements.

```typescript
// Récupérer tous les DevisSoumis pour un artisan
const logs = await publicClient.getLogs({
  address: escrowVaultAddress,
  event: parseAbiItem('event DevisSoumis(uint256 indexed chantierId, address indexed artisan, address indexed particulier, address token, uint256 devisAmount)'),
  args: { artisan: userAddress },
  fromBlock: deploymentBlock,
})
```

### Calcul du depositAmount avant approve

```typescript
const DEPOSIT_RATIO_BPS = 11_000n
const BPS_DENOMINATOR = 10_000n
const depositAmount = (devisAmount * DEPOSIT_RATIO_BPS) / BPS_DENOMINATOR
```

### Vérification du délai 48h avant triggerAutoValidation

```typescript
const jalon = await escrowVault.read.getCurrentJalon([chantierId])
const disponibleAt = jalon.finishedAt + 48n * 3600n
const canTrigger = BigInt(Math.floor(Date.now() / 1000)) >= disponibleAt
```
