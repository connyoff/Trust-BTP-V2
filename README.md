# Trust BTP — Backend Solidity

Séquestre intelligent instaurant la confiance entre particuliers et artisans.
Réseau cible : **Arbitrum Sepolia** (testnet soutenance) / Hardhat (local).

---

## Architecture des contrats

```
contracts/
├── EscrowVault.sol              Contrat principal — séquestre & paiements
├── ChantierNFT.sol              NFT soulbound — contrat immuable du chantier
├── TrustScoreRegistry.sol       Réputation on-chain des artisans (score 0–100)
├── libraries/
│   └── DataTypes.sol            Types partagés (enums, structs, constantes)
├── interfaces/
│   ├── IChantierNFT.sol
│   ├── IYieldProvider.sol
│   └── ITrustScoreRegistry.sol
└── yield/
    ├── AaveV3YieldProvider.sol  Adaptateur Aave V3 (yield optionnel)
    └── interfaces/
        └── IAavePool.sol
```

## Smart Contracts

| Contrat | Rôle |
|---|---|
| `EscrowVault.sol` | Point d'entrée unique — séquestre USDC, jalons, litiges, frais 2% |
| `ChantierNFT.sol` | ERC-721 Soulbound — dossier probatoire non-transférable par chantier |
| `TrustScoreRegistry.sol` | Score de réputation artisan (0–100), 4 tiers, gel en litige |
| `AaveV3YieldProvider.sol` | Yield opt-in — dépôt des fonds séquestrés dans Aave V3 |

---

## Flux principal

```
Artisan          submitDevis()       → Chantier créé (DevisSubmitted)
Particulier      rejectDevis()       → Clôture définitive (DevisRejected)
Particulier      acceptDevis()       → 110% déposés + NFT minté (Active)
                                       ↓ pour chaque jalon (max 5) :
Artisan          validateJalon()     → Preuve soumise, délai 48h démarre (Finished)
Particulier      acceptJalon()       → Validation anticipée → fonds libérés (Accepted)
N'importe qui    triggerAutoValidation() → Auto-validation après 48h sans réaction
Particulier      acceptJalonWithMinorReserves() → Réserves mineures (AcceptedWithReserves)
Particulier      acceptJalonWithMajorReserves() → Pause du chantier (Paused)
Artisan          acknowledgeReserves(true)  → Accepte déductions, paiement partiel
Artisan          acknowledgeReserves(false) → Refuse → Litige (InLitige)
Particulier      lifterReserves()    → Lève les réserves, déblocage (ReservesLifted)
Arbitre          resolveLitige()     → Tranche le litige (Active)
Particulier      cancelChantier()    → Annulation avant 1er jalon (Cancelled)
                                       ↓ à la fin du dernier jalon :
                 _avancerOuTerminer() → Buffer retourné + Trust Score mis à jour (Completed)
```

---

## Règles de gestion

### Dépôt & montants

| Règle | Valeur |
|---|---|
| Dépôt exigé | 110% du montant du devis |
| Nombre de jalons | 1 à 5 (défini à la soumission, immuable) |
| Somme des jalons | Doit être exactement égale au devis (100%) |
| Token accepté | USDC uniquement (6 décimales) |
| Commission plateforme | 2% prélevés sur chaque jalon libéré |
| Buffer (10% excédent) | Retourné au particulier à la clôture du chantier |

### Validation des jalons

| Règle | Détail |
|---|---|
| Principe | Le jalon est **validé automatiquement par défaut** |
| Délai de réaction | Le particulier a **48h** pour lever des réserves après la preuve artisan |
| Sans réaction → | Auto-validation déclenchable par n'importe qui (`triggerAutoValidation`) |
| Validation anticipée | Le particulier peut accepter avant 48h (`acceptJalon`) |

### Réserves mineures

| Règle | Valeur |
|---|---|
| Part bloquée | 10% du montant du jalon |
| Pénalité artisan (versée immédiatement à la plateforme) | 3% du montant du jalon |
| Paiement artisan immédiat | Jalon − 10% bloqué − 3% pénalité = 87% |
| Artisan accepte les réserves | Reçoit le paiement partiel, s'engage à corriger |
| Artisan refuse | Ouvre un litige → arbitrage |
| Particulier lève les réserves | Débloque les 10% vers l'artisan, avance au jalon suivant |

### Réserves majeures

| Règle | Détail |
|---|---|
| Effet | Le chantier est **suspendu** (Paused), aucun paiement |
| Le jalon entier est bloqué | Jusqu'à résolution par l'arbitre ou reprise par le particulier |
| Reprise | Particulier ou arbitre appelle `resumeChantier()`, le jalon repasse en Pending |

### Litige

| Règle | Détail |
|---|---|
| Ouverture | Artisan refuse les déductions de réserves mineures |
| Score artisan | Gelé pendant le litige (`freezeScore`) |
| Résolution | L'arbitre définit `blockedBps` (0–100%) + `penaltyBps` (0–50%) |
| Artisan en tort | Particulier remboursé du jalon − bloqué − pénalité |
| Particulier en tort | Artisan payé du jalon − bloqué − pénalité |
| Bloqué + pénalité | Versés à la trésorerie plateforme |
| Après résolution | Score mis à jour (impact négatif), chantier reprend |

### Annulation (avant 1er jalon)

| Règle | Détail |
|---|---|
| Conditions | Statut Active + 1er jalon non démarré (`Pending`) |
| Qui peut annuler | Uniquement le particulier |
| Artisan reçoit | Montant du **1er jalon** (compensation) |
| Particulier récupère | `depositAmount − 1er jalon` |
| Cas artisan | Non géré dans cette version |

### Yield DeFi (optionnel)

| Règle | Détail |
|---|---|
| Opt-in | Choisi par le particulier à l'acceptation du devis |
| Provider | Aave V3 (adaptateur pluggable via `IYieldProvider`) |
| Principe | 100% du dépôt (110% du devis) déposé dans Aave |
| Paiements jalons | Retrait du principal uniquement — le yield reste dans le provider |
| Collecte du yield | Owner appelle `collecterYield(token)` → trésorerie |
| Ajout futur | Un 2ème provider peut être branché sans redéployer le vault |

### NFT soulbound (ChantierNFT)

| Règle | Détail |
|---|---|
| Mint | 1 NFT par chantier, au moment de l'acceptation du devis |
| TokenId | Égal au `chantierId` |
| Détenteur | Le vault lui-même (pas dans les wallets des parties) |
| Affichage | Via la DApp uniquement (interrogation on-chain) |
| Données immuables | Artisan, particulier, token, montants, descriptions des jalons |
| Données mutables | **Statut de chaque jalon** (mis à jour automatiquement par le vault) |
| Transfert | **Bloqué** (soulbound) |
| Métadonnées | JSON base64 on-chain dans `tokenURI` |

### Trust Score (TrustScoreRegistry)

| Règle | Détail |
|---|---|
| Score initial | 50 / 100 |
| Mise à jour | Automatique à chaque clôture de chantier (appelé par le vault) |
| Jalons à temps (+) | +3 points par jalon livré dans les délais |
| Livraison globale (+) | +5 points si chantier livré dans les délais |
| Preuves soumises (+) | +2 points par preuve soumise |
| Litige (−) | −15 points par litige |
| Score gelé | Pendant un litige (pas de mise à jour possible) |

**Tiers de réputation :**

| Score | Tier | Avantages |
|---|---|---|
| 0–39 | Nouveau | Accès de base |
| 40–64 | Confirmé | Badge, mise en avant |
| 65–84 | Expert | Avance matériaux 30%, frais réduits |
| 85–100 | Elite | Commission 1%, avance maximale, badge Élite |

---

## Constantes clés

```solidity
DEPOSIT_RATIO_BPS       = 11_000   // 110% du devis
PLATFORM_FEE_BPS        = 200      // 2% par jalon
AUTO_VALIDATE_DELAY     = 48h
MINOR_RESERVE_BLOCK_BPS = 1_000    // 10% bloqué
MINOR_RESERVE_PENALTY_BPS = 300    // 3% pénalité
MAX_JALONS              = 5
```

---

## Commandes

```shell
# Installation
npm install

# Compilation
npx hardhat compile

# Tests
npx hardhat test test/EscrowVault.ts

# Déploiement local (Hardhat)
npx hardhat ignition deploy ignition/modules/TrustBTP.ts

# Déploiement Arbitrum Sepolia
npx hardhat keystore set ARBITRUM_SEPOLIA_PRIVATE_KEY
npx hardhat keystore set ARBITRUM_SEPOLIA_RPC_URL
npx hardhat ignition deploy ignition/modules/TrustBTP.ts --network arbitrumSepolia \
  --parameters ignition/parameters.json
```

### Exemple `ignition/parameters.json`

```json
{
  "TrustBTP": {
    "owner":        "0xYourOwnerAddress",
    "treasury":     "0xYourTreasuryAddress",
    "arbiter":      "0xYourArbiterAddress",
    "aavePool":     "0xBfC91D59fdAA134A4ED45f7B584cAf96D7792Eff",
    "usdcAddress":  "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d",
    "aUsdcAddress": "0x460b97BD498E1157530AEb3086301d5225b91216"
  }
}
```

---

## TODO

- [ ] Paramétrage des pénalités (actuellement codées en dur)
- [ ] Multi-token (EURC, DAI...)
- [ ] 2ème provider de yield (Morpho)
- [ ] Délais par jalon configurables (actuellement heuristique 7j/jalon)
