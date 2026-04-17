# Trust BTP — Frontend

Interface web du protocole de séquestre décentralisé Trust BTP.
Paiements par jalons, yield DeFi (Aave V3), réputation on-chain, NFT soulbound.

---

## Stack technique

| Technologie | Version | Rôle |
|---|---|---|
| **Next.js** | 16 (App Router) | Framework React SSR |
| **TypeScript** | 5 | Typage statique |
| **Tailwind CSS** | v4 | Styles utilitaires |
| **shadcn/ui** | — | Composants UI (Button, Card, Input, Badge...) |
| **wagmi** | v3 | Hooks React pour interactions blockchain |
| **viem** | v2 | Client Ethereum bas niveau (lecture, ABI, utils, logs) |
| **Reown AppKit** | v1 | Modal de connexion wallet (MetaMask, WalletConnect...) |
| **TanStack React Query** | v5 | Cache et synchronisation des données on-chain |
| **lucide-react** | — | Icônes |

---

## Arborescence

```
src/
├── app/
│   ├── globals.css              Thème dark teal + grille de fond
│   ├── layout.tsx               Layout racine avec WalletProvider
│   ├── page.tsx                 Landing (non connecté) ou Dashboard
│   ├── nouveau-devis/
│   │   └── page.tsx             Formulaire de soumission de devis (artisan)
│   └── chantier/[id]/
│       └── page.tsx             Détail chantier + toutes les actions
├── components/
│   ├── shared/
│   │   ├── Header.tsx           Logo Trust BTP + bouton retour + ConnectButton
│   │   ├── Footer.tsx           Réseau et token
│   │   ├── Layout.tsx           Wrapper header/main/footer
│   │   ├── ConnectButton.tsx    Bouton AppKit wallet
│   │   └── NotConnected.tsx     Landing page (hero, étapes, deux publics)
│   └── chantier/
│       ├── StatusBadge.tsx      Badges colorés ChantierStatus / JalonStatus
│       ├── TrustScoreBadge.tsx  Score et tier de réputation artisan
│       ├── JalonRow.tsx         Ligne jalon avec icône, montant, actions inline
│       ├── ChantierAccordionCard.tsx  Carte accordéon (barre de progression + jalons)
│       ├── StatsBar.tsx         4 KPIs agrégés (actifs, escrow, jalons, litiges)
│       ├── SubmitDevisForm.tsx  Formulaire 1–5 jalons avec calcul automatique 110%
│       └── Dashboard.tsx        Stats + liste accordéon des chantiers
├── hooks/                       Toute interaction blockchain passe par ici
│   ├── useChantier.ts           Lecture struct Chantier + jalons
│   ├── useChantiersByAddress.ts IDs des chantiers via getLogs(DevisSoumis)
│   ├── useSubmitDevis.ts        Artisan — soumet un devis
│   ├── useAcceptDevis.ts        Particulier — approve USDC puis acceptDevis (2 tx)
│   ├── useJalonActions.ts       Toutes les actions jalons et cycle de vie
│   └── useTrustScore.ts         Lecture TrustScoreRegistry.getStats()
├── lib/
│   ├── contracts.ts             ABIs et adresses (depuis .env.local)
│   ├── utils.ts                 formatUsdc, shortAddress, parseUsdc, hashProof
│   └── client.ts                publicClient viem (hardhat ou arbitrumSepolia)
├── types/
│   └── contracts.ts             Enums et interfaces TypeScript (Chantier, Jalon...)
├── config/
│   └── index.tsx                Config wagmi + Reown AppKit
└── context/
    └── index.tsx                WagmiProvider + QueryClientProvider
```

---

## Pour démarrer

**1. Installer les dépendances**
```bash
npm install
```

**2. Configurer les variables d'environnement**
```bash
cp .env.local.example .env.local
```

Remplir `.env.local` :
```env
# Reown AppKit — https://dashboard.reown.com
NEXT_PUBLIC_PROJECT_ID=your_project_id

# Réseau : "hardhat" (local) ou "arbitrumSepolia" (testnet)
NEXT_PUBLIC_NETWORK=hardhat

# Adresses des contrats (voir section ci-dessous)
NEXT_PUBLIC_ESCROW_VAULT_ADDRESS=0x...
NEXT_PUBLIC_CHANTIER_NFT_ADDRESS=0x...
NEXT_PUBLIC_TRUST_SCORE_REGISTRY_ADDRESS=0x...
```

**3. Lancer le serveur de développement**
```bash
npm run dev          # http://localhost:3000
npm run dev:poll     # WSL / Docker (polling filesystem)
```

**4. Build de production**
```bash
npm run build
npm run lint
```

---

## Après déploiement des contrats Hardhat

```bash
# Dans le dossier backend/
npx hardhat node                                                # lancer un nœud local
npx hardhat ignition deploy ignition/modules/TrustBTP.ts       # déployer les contrats
```

Récupérer les adresses dans :
```
backend/ignition/deployments/chain-31337/deployed_addresses.json
```

Les copier dans `frontend/.env.local` :
```env
NEXT_PUBLIC_ESCROW_VAULT_ADDRESS=0x...     # TrustBTP#EscrowVault
NEXT_PUBLIC_CHANTIER_NFT_ADDRESS=0x...     # TrustBTP#ChantierNFT
NEXT_PUBLIC_TRUST_SCORE_REGISTRY_ADDRESS=0x...  # TrustBTP#TrustScoreRegistry
```

Pour Arbitrum Sepolia :
```bash
npx hardhat ignition deploy ignition/modules/TrustBTP.ts \
  --network arbitrumSepolia --parameters ignition/parameters.json
# Les adresses seront dans : deployments/chain-421614/deployed_addresses.json
# Passer NEXT_PUBLIC_NETWORK=arbitrumSepolia dans .env.local
```

---

## Règle d'architecture

Toute interaction blockchain doit passer par les hooks dans `src/hooks/`.
Ne jamais appeler `useReadContract` ou `useWriteContract` directement depuis un composant ou une page.

```typescript
// ✅ Correct
const { chantier, jalons } = useChantier(chantierId)
const { submitDevis, isPending } = useSubmitDevis()

// ❌ À éviter dans les composants
const { data } = useReadContract({ address: ..., abi: ..., functionName: 'chantiers' })
```

---

## Documents de référence

| Fichier | Rôle |
|---|---|
| `../doc/business-rules.md` | Règles métier complètes (statuts, flux, finances) |
| `../doc/contract-abi.md` | Toutes les fonctions publiques des contrats |
| `../doc/architecture.md` | Architecture globale frontend ↔ backend |
| `../backend/README.md` | Guide backend (compilation, tests, déploiement) |
