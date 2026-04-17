# Trust BTP — Architecture globale

> Référence technique pour le développement frontend et la compréhension du système.

---

## 1. Vue d'ensemble

Trust BTP est un protocole de séquestre décentralisé pour les chantiers BTP. Il met en relation des artisans et des particuliers via des smart contracts sur **Arbitrum Sepolia**, avec une interface web **Next.js** qui lit et écrit sur la chaîne via **ethers.js / wagmi**.

```
┌─────────────────────────────────────────────────────────┐
│                     Navigateur / DApp                   │
│                  (Next.js + TypeScript)                 │
│                                                         │
│   ┌─────────────┐  ┌──────────────┐  ┌──────────────┐   │
│   │ Wallet      │  │ Lecture      │  │ Écriture     │   │
│   │ (MetaMask / │  │ (ethers.js / │  │ (wagmi /     │   │
│   │  WalletConnect)│ viem)        │  │  ethers.js)  │   │
│   └──────┬──────┘  └──────┬───────┘  └──────┬───────┘   │
└──────────┼────────────────┼─────────────────┼───────────┘
           │                │                 │
           ▼                ▼                 ▼
┌──────────────────────────────────────────────────────────┐
│                  Arbitrum Sepolia (L2)                   │
│                                                          │
│  ┌─────────────────────────────────────────────────────┐ │
│  │               EscrowVault.sol (principal)           │ │
│  │  - Cycle de vie complet des chantiers               │ │
│  │  - Gestion des fonds (USDC)                         │ │
│  │  - Paiements par jalons                             │ │
│  │  - Réserves, litiges, annulation                    │ │
│  └──────────────┬──────────────┬────────────────────────┘ │
│                 │              │                          │
│        ┌────────▼──────┐  ┌───▼────────────────────┐      │
│        │ ChantierNFT   │  │ TrustScoreRegistry     │      │
│        │ (ERC-721      │  │ - Réputation artisan   │      │
│        │  soulbound)   │  │ - Score 0–100          │      │
│        │ - 1 NFT /     │  │ - 4 tiers              │      │
│        │   chantier    │  │ - Gel/dégel litige     │      │
│        │ - Statuts      │  └────────────────────────┘     │
│        │   mutables    │                                  │
│        └───────────────┘                                  │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐  │
│  │         AaveV3YieldProvider.sol (optionnel)         │  │
│  │  - Dépôt du capital dans Aave V3                    │  │
│  │  - Génération de yield sur les fonds séquestrés     │  │
│  │  - Interface pluggable (IYieldProvider)             │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                           │
│  ┌──────────┐                                             │
│  │  USDC    │  ERC-20, 6 décimales                        │
│  └──────────┘                                             │
└──────────────────────────────────────────────────────────┘
```

---

## 2. Backend — Smart contracts

### 2.1 Réseau et outillage

| Paramètre | Valeur |
|---|---|
| Réseau cible | **Arbitrum Sepolia** (testnet soutenance) |
| Réseau local | **Hardhat** |
| Langage | **Solidity 0.8.28** |
| Framework de test | **Hardhat v3** + **Mocha** / **Chai** |
| Framework de déploiement | **Hardhat Ignition** |
| Bibliothèque | **OpenZeppelin Contracts v5.6.1** |
| Compilateur | `viaIR: true` + optimizer (requis pour éviter *stack too deep*) |

### 2.2 Contrats déployés

#### `EscrowVault.sol` — Contrat principal

Point d'entrée unique pour toutes les interactions utilisateur. Orchestre l'intégralité du cycle de vie d'un chantier.

**Rôle** : séquestre des fonds USDC, gestion des jalons, appels vers ChantierNFT et TrustScoreRegistry.

**Fonctions publiques exposées au frontend** :

| Fonction | Rôle | Appelant |
|---|---|---|
| `submitDevis(...)` | Crée un chantier, retourne `chantierId` | Artisan |
| `rejectDevis(chantierId)` | Refuse le devis, clôture | Particulier |
| `acceptDevis(chantierId, yieldOptIn)` | Signe + dépose 110% en USDC | Particulier |
| `validateJalon(chantierId, proofHash)` | Soumet la preuve, lance le délai 48h | Artisan |
| `acceptJalon(chantierId)` | Valide manuellement avant 48h | Particulier |
| `triggerAutoValidation(chantierId)` | Valide automatiquement après 48h | N'importe qui |
| `acceptJalonWithMinorReserves(chantierId, clientProofHash)` | Réserves mineures (10% bloqué) | Particulier |
| `acceptJalonWithMajorReserves(chantierId, clientProofHash)` | Réserves majeures (pause) | Particulier |
| `acknowledgeReserves(chantierId, accept)` | Accepte ou refuse les déductions | Artisan |
| `lifterReserves(chantierId)` | Lève les réserves, débloque 10% | Particulier |
| `resolveLitige(chantierId, artisanEnTort, blockedBps, penaltyBps)` | Tranche le litige | Arbitre |
| `resumeChantier(chantierId)` | Reprend après réserves majeures | Particulier / Arbitre |
| `cancelChantier(chantierId)` | Annule avant le 1er jalon | Particulier |
| `getCurrentJalon(chantierId)` | Lecture : jalon en cours | View |
| `getJalon(chantierId, jalonIndex)` | Lecture : jalon spécifique | View |
| `getAllJalons(chantierId)` | Lecture : tous les jalons | View |
| `chantiers(chantierId)` | Lecture : données du chantier (public mapping) | View |
| `setAllowedToken(token, bool)` | Autorise un token | Owner |
| `setYieldProvider(address)` | Change le provider DeFi | Owner |
| `setArbiter(address)` | Change l'arbitre | Owner |
| `collecterFrais(token)` | Collecte frais vers trésorerie | Owner |
| `collecterYield(token)` | Collecte yield vers trésorerie | Owner |

**Prérequis avant `acceptDevis()`** : le particulier doit appeler `IERC20(usdc).approve(escrowVault, depositAmount)` d'abord (2 transactions). EIP-2612 permit prévu en TODO.

---

#### `ChantierNFT.sol` — NFT soulbound

Contrat ERC-721 avec transfert bloqué (`Soulbound`). Détenu par le vault, jamais dans les wallets.

**Rôle** : preuve immuable du contrat de chantier, accessible en lecture via la DApp.

| Fonction | Rôle | Appelant |
|---|---|---|
| `mintChantier(...)` | Minte le NFT (tokenId = chantierId) | Vault (onlyOwner) |
| `updateJalonStatus(chantierId, jalonIndex, newStatus)` | Met à jour le statut d'un jalon | Vault (onlyOwner) |
| `getDevisData(chantierId)` | Retourne les données immuables du chantier | View |
| `getJalonStatuses(chantierId)` | Retourne tous les statuts de jalons | View |
| `getJalonStatus(chantierId, jalonIndex)` | Retourne le statut d'un jalon | View |
| `tokenURI(chantierId)` | Métadonnées JSON base64 on-chain | View |
| `ownerOf(chantierId)` | Retourne l'adresse du vault | View (ERC-721) |

**Note** : la DApp n'appelle jamais `mintChantier` ou `updateJalonStatus` directement — ces appels sont faits automatiquement par le vault.

---

#### `TrustScoreRegistry.sol` — Réputation

Registre on-chain des scores de réputation des artisans.

| Fonction | Rôle | Appelant |
|---|---|---|
| `getScore(artisan)` | Score actuel (0–100) | View |
| `getTier(artisan)` | Tier de réputation (Nouveau/Confirmé/Expert/Élite) | View |
| `getStats(artisan)` | Score + tier + chantiers + litiges + gel | View |
| `setEscrowVault(address)` | Configure l'adresse du vault | Owner |
| `updateScore(...)` | Met à jour le score après chantier | Vault |
| `freezeScore(artisan, chantierId)` | Gèle le score pendant un litige | Vault |
| `unfreezeScore(artisan, chantierId)` | Dégèle le score après résolution | Vault |

---

#### `AaveV3YieldProvider.sol` — Yield DeFi

Adaptateur Aave V3 pour générer du yield sur les fonds séquestrés.

| Fonction | Rôle | Appelant |
|---|---|---|
| `deposit(token, amount)` | Dépose dans Aave (reçoit aTokens) | Vault |
| `withdraw(token, amount, recipient)` | Retire le principal | Vault |
| `withdrawAll(token, recipient)` | Retire tout (capital + yield) | Vault |
| `totalValue(token)` | Valeur totale des aTokens | View |
| `pendingYield(token, principal)` | Yield disponible à collecter | View |
| `registerToken(token, aToken)` | Enregistre une paire token/aToken | Owner |

---

### 2.3 Déploiement et configuration

**Ordre de déploiement (Hardhat Ignition)** :

```
1. TrustScoreRegistry(owner)
2. ChantierNFT(owner)
3. EscrowVault(owner, treasury, arbiter, registry, nft)
4. AaveV3YieldProvider(owner, aavePool)

Post-déploiement :
  registry.setEscrowVault(vault)
  nft.transferOwnership(vault)
  vault.setYieldProvider(aave)
  vault.setAllowedToken(USDC, true)
  aave.registerToken(USDC, aUSDC)
```

**Adresses Arbitrum Sepolia** :
- Aave Pool : `0xBfC91D59fdAA134A4ED45f7B584cAf96D7792Eff`
- USDC : `0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d`
- aUSDC : `0x460b97BD498E1157530AEb3086301d5225b91216`

---

## 3. Frontend — Next.js

### 3.1 Stack technique prévu

| Technologie | Rôle |
|---|---|
| **Next.js 15** (App Router) | Framework React SSR/SSG |
| **TypeScript** | Typage statique |
| **Tailwind CSS** + **shadcn/ui** | Interface et composants |
| **wagmi v2** + **viem** | Connexion wallet, lecture/écriture on-chain |
| **RainbowKit** | Modal de connexion wallet |
| **ethers.js v6** | Interactions alternatives avec les contrats |
| **React Query** (via wagmi) | Cache des données on-chain |

### 3.2 Pages principales

| Page | Rôle | Utilisateur |
|---|---|---|
| `/` | Landing page, connexion wallet | Tous |
| `/artisan/dashboard` | Liste des chantiers artisan, TrustScore | Artisan |
| `/artisan/devis/new` | Formulaire soumission devis | Artisan |
| `/artisan/chantier/[id]` | Détail chantier, actions artisan | Artisan |
| `/particulier/dashboard` | Liste des chantiers particulier | Particulier |
| `/particulier/chantier/[id]` | Détail chantier, actions particulier | Particulier |
| `/chantier/[id]` | Vue publique (lecture NFT) | Tous |
| `/admin` | Dashboard owner (frais, yield, arbitre) | Owner |

### 3.3 Composants clés

| Composant | Rôle |
|---|---|
| `ChantierTimeline` | Affiche l'état des jalons avec statuts colorés |
| `JalonCard` | Carte d'un jalon (description, montant, statut, actions) |
| `TrustScoreBadge` | Badge de réputation artisan (tier + score) |
| `DepositApproveFlow` | Flow en 2 étapes : `approve` puis `acceptDevis` |
| `ProofHashInput` | Saisie et hachage keccak256 de la preuve artisan |
| `NFTViewer` | Lecture et affichage des données on-chain du NFT |
| `LitigePanel` | Interface arbitrage pour l'arbitre |

---

## 4. Interactions frontend ↔ backend

### 4.1 Flux de connexion

```
Utilisateur ouvre la DApp
  → RainbowKit affiche les wallets disponibles
  → Connexion MetaMask / WalletConnect
  → wagmi détecte l'adresse connectée
  → DApp lit le rôle via les chantiers on-chain
     (artisan = chantiers[n].artisan == address)
     (particulier = chantiers[n].particulier == address)
```

### 4.2 Flux de lecture (pas de gas)

```
Frontend
  → useContractRead / readContract (wagmi/viem)
  → RPC Arbitrum Sepolia (Alchemy / Infura / public)
  → EscrowVault.chantiers(id)
  → EscrowVault.getAllJalons(id)
  → ChantierNFT.getDevisData(id)
  → ChantierNFT.getJalonStatuses(id)
  → TrustScoreRegistry.getStats(artisan)
```

### 4.3 Flux d'écriture (transaction on-chain)

```
Exemple : acceptation d'un jalon

1. Frontend appelle writeContract({ address: escrowVault, abi, functionName: 'acceptJalon', args: [chantierId] })
2. wagmi prépare la transaction et la signe via MetaMask
3. La transaction est broadcast sur Arbitrum Sepolia
4. EscrowVault.acceptJalon() s'exécute :
   - Libère 98% du montant à l'artisan
   - Met à jour le statut interne
   - Appelle ChantierNFT.updateJalonStatus()
   - Si dernier jalon : retourne buffer + met à jour TrustScore
5. Événement JalonAccepte émis
6. Frontend écoute l'événement ou relit les données (useWatchContractEvent)
7. UI se met à jour automatiquement
```

### 4.4 Flux d'écoute d'événements

Le frontend peut écouter les événements on-chain pour des mises à jour en temps réel :

```typescript
useWatchContractEvent({
  address: escrowVaultAddress,
  abi: escrowVaultAbi,
  eventName: 'JalonAccepte',
  onLogs: (logs) => { /* rafraîchir UI */ }
})
```

Événements clés à écouter :

| Événement | Contrat | Usage frontend |
|---|---|---|
| `DevisSoumis` | EscrowVault | Notifier le particulier |
| `DevisAccepte` | EscrowVault | Démarrer le suivi chantier |
| `JalonValide` | EscrowVault | Notifier le particulier (délai 48h) |
| `JalonAccepte` | EscrowVault | Afficher paiement effectué |
| `JalonAccepteAvecReserves` | EscrowVault | Notifier l'artisan |
| `LitigeOuvert` | EscrowVault | Notifier l'arbitre |
| `LitigeResolu` | EscrowVault | Afficher la résolution |
| `ChantierTermine` | EscrowVault | Clôturer l'affichage |
| `JalonStatusMisAJour` | ChantierNFT | Rafraîchir le NFT viewer |
| `ScoreUpdated` | TrustScoreRegistry | Mettre à jour le badge artisan |

### 4.5 ABIs et adresses

Les ABIs sont générés par Hardhat à la compilation :
```
backend/artifacts/contracts/EscrowVault.sol/EscrowVault.json
backend/artifacts/contracts/ChantierNFT.sol/ChantierNFT.json
backend/artifacts/contracts/TrustScoreRegistry.sol/TrustScoreRegistry.json
```

Les adresses de déploiement sont disponibles après `npx hardhat ignition deploy` dans :
```
backend/ignition/deployments/chain-<chainId>/deployed_addresses.json
```

---

## 5. Sécurité et contraintes

| Contrainte | Détail |
|---|---|
| Reentrancy | `ReentrancyGuard` sur toutes les fonctions de transfert |
| Checks-Effects-Interactions | État mis à jour avant tout transfert externe |
| Token whitelist | Seuls les tokens approuvés par l'owner sont acceptés (USDC) |
| Soulbound | NFT non-transférable — empêche la revente ou le transfert |
| Custom errors | Erreurs Solidity typées (gas-efficient) |
| Approbation ERC-20 | L'utilisateur doit `approve` avant `acceptDevis` — à améliorer avec EIP-2612 |
| Rôles stricts | Chaque fonction vérifie l'identité de l'appelant (artisan / particulier / arbitre / owner) |
