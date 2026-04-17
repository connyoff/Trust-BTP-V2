# Trust BTP — Règles de gestion

> Document de référence exhaustif pour le développement frontend.
> Source : smart contracts Solidity + README backend.

---

## 1. Rôles utilisateur

| Rôle | Description | Permissions clés |
|---|---|---|
| **Artisan** | Prestataire qui soumet le devis | `submitDevis`, `validateJalon`, `acknowledgeReserves` |
| **Particulier** | Client qui finance et valide | `acceptDevis`, `rejectDevis`, `acceptJalon`, `acceptJalonWithMinorReserves`, `acceptJalonWithMajorReserves`, `lifterReserves`, `cancelChantier` |
| **Arbitre** | Tiers de confiance (adresse unique) | `resolveLitige`, `resumeChantier` |
| **Owner** | Administrateur de la plateforme (multisig) | `setAllowedToken`, `setYieldProvider`, `setArbiter`, `collecterFrais`, `collecterYield` |
| **N'importe qui** | Sans restriction d'identité | `triggerAutoValidation` (après délai) |

---

## 2. Cycle de vie d'un chantier

### 2.1 Statuts du chantier (`ChantierStatus`)

| Valeur | Index | Signification |
|---|---|---|
| `DevisSubmitted` | 0 | Devis soumis par l'artisan — en attente de signature du particulier |
| `DevisRejected` | 1 | Particulier a refusé le devis — chantier clôturé définitivement |
| `Active` | 2 | Devis signé, fonds déposés — travaux en cours |
| `Paused` | 3 | Réserves majeures levées — chantier suspendu, aucun paiement |
| `InLitige` | 4 | Litige en cours d'arbitrage |
| `Completed` | 5 | Tous les jalons validés — fonds entièrement libérés |
| `Cancelled` | 6 | Annulé par le particulier avant le 1er jalon |

### 2.2 Flux de transitions

```
[submitDevis]
      ↓
DevisSubmitted
      ├─[rejectDevis]──────────────────→ DevisRejected (terminal)
      └─[acceptDevis]──────────────────→ Active
                                              │
                         ┌────────────────────┤
                         │    (pour chaque jalon)
                         │
                    validateJalon (artisan)
                         ↓
                    [jalon = Finished]
                         │
              ┌──────────┼─────────────┐
              │          │             │
        acceptJalon  triggerAuto  acceptJalonWith
        (particulier) (48h+, any) MinorReserves
              │          │             │
              └────┬─────┘     AcceptedWithReserves
                   │                   │
              [jalon = Accepted]        ├─[acknowledgeReserves(true)]
                   │                   │       ↓
            _avancerOuTerminer   PaidWithReserves
                   │                   │
          (dernier jalon?)      [lifterReserves]
             ├── Non: index++           │
             └── Oui: Completed   ReservesLifted
                                        │
                                  _avancerOuTerminer
                                        │
              acceptJalonWithMajorReserves
                         ↓
                       Paused
                         │
                  resumeChantier (particulier | arbitre)
                         ↓
                       Active (jalon remis à Pending)

              acknowledgeReserves(false)
                         ↓
                      InLitige
                         │
                  resolveLitige (arbitre)
                         ↓
                      Active → _avancerOuTerminer

         cancelChantier (particulier, jalon 0 non démarré)
                         ↓
                     Cancelled (terminal)
```

---

## 3. Statuts d'un jalon (`JalonStatus`)

| Valeur | Index | Signification |
|---|---|---|
| `Pending` | 0 | Non réalisé — en attente |
| `Finished` | 1 | Artisan a soumis la preuve — délai 48h en cours |
| `Accepted` | 2 | Validé (manuellement ou auto) — fonds libérés |
| `AcceptedWithReserves` | 3 | Accepté avec réserves (mineures ou majeures) |
| `PaidWithReserves` | 4 | Artisan a accusé réception — paiement partiel effectué |
| `InLitige` | 5 | Artisan a refusé les déductions — arbitrage |
| `ReservesLifted` | 6 | Réserves levées — solde libéré à l'artisan |

**Le statut de chaque jalon est reflété en temps réel dans le NFT.**

---

## 4. Règles financières

### 4.1 Dépôt

| Règle | Valeur |
|---|---|
| Montant déposé | **110%** du montant du devis (`DEPOSIT_RATIO_BPS = 11_000`) |
| Composition | 100% = somme des jalons (devis) + 10% = buffer de sécurité |
| Token accepté | **USDC uniquement** (6 décimales) — autres stablecoins prévus ultérieurement |
| Moment du dépôt | Lors de l'appel à `acceptDevis()` par le particulier |
| Prérequis | Le particulier doit avoir approuvé (`approve`) le vault pour `depositAmount` avant |

### 4.2 Commission plateforme

| Règle | Valeur |
|---|---|
| Taux | **2%** du montant brut de chaque jalon (`PLATFORM_FEE_BPS = 200`) |
| Prélèvement | Automatique à chaque libération de jalon |
| Bénéficiaire | Trésorerie (`treasury`) — collecte manuelle via `collecterFrais()` |
| Cas réserves mineures | La pénalité (3%) est prélevée immédiatement en plus des 2% |

### 4.3 Libération d'un jalon (chemin nominal)

```
montant brut du jalon
  − 2% commission plateforme
  = montant net → versé à l'artisan
```

### 4.4 Libération avec réserves mineures

```
montant brut du jalon
  − 10% bloqué (en attente de correction)
  − 3% pénalité (versé immédiatement à la plateforme)
  = 87% → versé à l'artisan immédiatement (sur acknowledgeReserves)

Après lifterReserves() :
  + 10% débloqué → versé à l'artisan
```

### 4.5 Buffer à la clôture

```
À la clôture du dernier jalon :
  buffer (10% du devis = depositAmount − devisAmount)
  → retourné intégralement au particulier
```

### 4.6 Annulation avant 1er jalon

```
depositAmount (110%)
  − jalons[0].amount → versé à l'artisan (compensation)
  = reste → retourné au particulier
```

---

## 5. Règle des jalons

### 5.1 Contraintes à la soumission du devis

| Contrainte | Détail |
|---|---|
| Nombre | Entre 1 et 5 jalons (`MAX_JALONS = 5`) |
| Somme | `sum(jalonAmounts) == devisAmount` obligatoire |
| Immuabilité | Descriptions et montants **figés à la soumission** |
| Index courant | Commence à 0, avance automatiquement |

### 5.2 Validation automatique (48h)

- L'artisan appelle `validateJalon()` → statut passe à `Finished`, horodatage enregistré.
- Le particulier dispose de **48 heures exactement** pour réagir.
- Sans réaction → n'importe qui peut appeler `triggerAutoValidation()`.
- Le jalon est alors libéré comme s'il avait été accepté manuellement.
- Le particulier peut aussi accepter **avant** 48h via `acceptJalon()`.

### 5.3 Réserves mineures

1. Particulier appelle `acceptJalonWithMinorReserves(chantierId, clientProofHash)`.
2. 10% bloqué + 3% pénalité calculés automatiquement.
3. Artisan reçoit `LitigeOuvert` ou `ReservesAccusees` selon son choix.
4. Si `acknowledgeReserves(true)` : paiement partiel immédiat (87%), jalon en `PaidWithReserves`.
5. Si `acknowledgeReserves(false)` : litige ouvert, score gelé.
6. Particulier appelle `lifterReserves()` après correction → 10% débloqués, jalon suivant.

### 5.4 Réserves majeures

1. Particulier appelle `acceptJalonWithMajorReserves(chantierId, clientProofHash)`.
2. Chantier passe en `Paused` — aucun paiement possible.
3. Le jalon entier est bloqué.
4. Reprise via `resumeChantier()` (particulier ou arbitre) → jalon remis à `Pending`.
5. L'artisan doit re-soumettre sa preuve via `validateJalon()`.

---

## 6. Règles de litige

| Étape | Détail |
|---|---|
| Déclenchement | `acknowledgeReserves(false)` par l'artisan |
| Effet immédiat | Score artisan gelé (`freezeScore`) |
| Statut chantier | `InLitige` |
| Résolution | L'arbitre appelle `resolveLitige(chantierId, artisanEnTort, blockedBps, penaltyBps)` |
| `blockedBps` | 0–10 000 (BPS) du montant jalon conservé par la plateforme |
| `penaltyBps` | 0–5 000 (BPS) de pénalité supplémentaire |

**Si artisan en tort :**
```
particulier reçoit : jalon − blockedBps% − penaltyBps%
plateforme garde   : blockedBps% + penaltyBps%
```

**Si particulier en tort :**
```
artisan reçoit     : jalon − blockedBps% − penaltyBps%
plateforme garde   : blockedBps% + penaltyBps%
```

Après résolution : score mis à jour (pénalité litige = −15 pts), chantier reprend.

---

## 7. Yield DeFi (optionnel)

| Règle | Détail |
|---|---|
| Opt-in | Paramètre `yieldOptIn` au moment de `acceptDevis()` |
| Provider actuel | Aave V3 (`AaveV3YieldProvider`) |
| Extensibilité | Interface `IYieldProvider` — nouveau provider via `setYieldProvider()` sans redéploiement |
| Fonctionnement | 100% du dépôt (110% devis) envoyé à Aave → génère des aTokens |
| Paiements jalons | Retrait du **principal exact** depuis Aave → le yield reste accumulé |
| Collecte yield | Owner appelle `collecterYield(token)` → trésorerie |
| Impact utilisateur | Transparent pour l'artisan et le particulier |

---

## 8. NFT soulbound (ChantierNFT)

| Règle | Détail |
|---|---|
| Moment du mint | Lors de `acceptDevis()` |
| Quantité | **1 NFT par chantier** |
| `tokenId` | Égal au `chantierId` (accès direct) |
| Détenteur | Le vault — **jamais dans les wallets des utilisateurs** |
| Transfert | **Bloqué** — toute tentative lève `Soulbound` |
| Affichage | Via la DApp uniquement (lecture on-chain) |

**Données immuables stockées dans le NFT :**
- `chantierId`, `artisan`, `particulier`, `token`
- `devisAmount`, `depositAmount`, `jalonCount`
- `submittedAt`, `acceptedAt`
- Descriptions et montants de chaque jalon

**Données mutables :**
- Statut de chaque jalon (`JalonStatus[]`) — mis à jour automatiquement par le vault à chaque transition

**Métadonnées :** JSON base64 on-chain via `tokenURI(chantierId)`, contient attributs + tableau des jalons.

---

## 9. Trust Score

### 9.1 Mécanisme

| Règle | Détail |
|---|---|
| Score de départ | **50** / 100 pour tout nouvel artisan |
| Plage | 0 à 100 (écrêtage automatique) |
| Mise à jour | Automatique à chaque `Completed` (appelé par le vault) |
| Gel | Pendant un litige — aucune mise à jour possible |

### 9.2 Barème de points par chantier

| Événement | Points |
|---|---|
| Jalon livré dans les délais | +3 par jalon |
| Chantier livré dans les délais | +5 |
| Preuve soumise | +2 par preuve (plafonné au nombre de jalons) |
| Litige durant le chantier | −15 |

### 9.3 Tiers de réputation

| Score | Tier | Index enum | Avantages |
|---|---|---|---|
| 0–39 | `Nouveau` | 0 | Accès de base |
| 40–64 | `Confirme` | 1 | Badge profil, mise en avant |
| 65–84 | `Expert` | 2 | Avance matériaux 30%, frais réduits |
| 85–100 | `Elite` | 3 | Commission 1%, avance maximale, badge Élite |

---

## 10. Contraintes globales

| Contrainte | Valeur |
|---|---|
| Token autorisé | USDC (`allowedTokens[usdc] == true`) |
| Max jalons | 5 |
| Somme jalons = devis | Obligatoire à la création |
| Délai auto-validation | 48 heures |
| Annulation artisan | Non implémentée dans cette version |
| Devis refusé → nouveau devis | L'artisan doit créer un nouveau `submitDevis` |
| Double-dépôt | Impossible — NFT vérifie `_ownerOf(chantierId) != 0` |

---

## 11. Événements émis (pour indexation frontend)

### EscrowVault

| Événement | Données | Déclencheur |
|---|---|---|
| `DevisSoumis` | chantierId, artisan, particulier, token, devisAmount | `submitDevis` |
| `DevisAccepte` | chantierId, particulier, depositAmount, yieldOptIn | `acceptDevis` |
| `DevisRefuse` | chantierId, particulier | `rejectDevis` |
| `JalonValide` | chantierId, jalonIndex, proofHash | `validateJalon` |
| `JalonAccepte` | chantierId, jalonIndex, montantLibere | `acceptJalon`, `triggerAutoValidation`, `resolveLitige` |
| `JalonAutoValide` | chantierId, jalonIndex | `triggerAutoValidation` |
| `JalonAccepteAvecReserves` | chantierId, jalonIndex, majeur, clientProofHash | `acceptJalonWith*Reserves` |
| `ReservesAccusees` | chantierId, jalonIndex, montantPaye | `acknowledgeReserves(true)` |
| `ReservesLevees` | chantierId, jalonIndex, montantDebloque | `lifterReserves` |
| `LitigeOuvert` | chantierId, jalonIndex | `acknowledgeReserves(false)` |
| `LitigeResolu` | chantierId, jalonIndex, artisanEnTort, montantArtisan, remboursement, penalite | `resolveLitige` |
| `ChantierTermine` | chantierId | auto (dernier jalon) |
| `ChantierAnnule` | chantierId | `cancelChantier` |
| `ChantierEnPause` | chantierId, jalonIndex | `acceptJalonWithMajorReserves` |
| `ChantierRepris` | chantierId, jalonIndex | `resumeChantier` |

### ChantierNFT

| Événement | Données | Déclencheur |
|---|---|---|
| `ChantierMinte` | chantierId, vault | `mintChantier` (via acceptDevis) |
| `JalonStatusMisAJour` | chantierId, jalonIndex, newStatus | toute transition de statut jalon |

### TrustScoreRegistry

| Événement | Données | Déclencheur |
|---|---|---|
| `ScoreUpdated` | artisan, oldScore, newScore, newTier | clôture chantier ou litige |
| `ScoreFrozen` | artisan, chantierId | ouverture litige |
| `ScoreUnfrozen` | artisan, chantierId | résolution litige |
