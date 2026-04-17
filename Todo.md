Récapitulatif de l'implémentation
Structure des contrats

contracts/
├── libraries/
│   └── DataTypes.sol          — structs, enums, constantes (BPS, delays, pénalités)
├── interfaces/
│   ├── IYieldProvider.sol     — interface pour les adaptateurs DeFi
│   └── ITrustScoreRegistry.sol — interface pour la réputation artisan
├── yield/
│   ├── interfaces/
│   │   └── IAavePool.sol      — interface minimale Aave V3
│   └── AaveV3YieldProvider.sol — adaptateur Aave V3 (pluggable)
├── mocks/
│   └── ERC20Mock.sol          — token fictif pour les tests
├── TrustScoreRegistry.sol     — réputation on-chain (score 0–100, 4 tiers)
└── EscrowVault.sol            — contrat principal (≈ 400 lignes)
Ce que couvre EscrowVault

Flow	Couvert
Création chantier (110% dépôt)	✅
Acceptation artisan	✅
Validation jalon + preuve	✅
Acceptation sans réserve (100% artisan)	✅
Auto-validation 48h	✅
Réserves mineures (10% bloqué + 3% pénalité)	✅
Artisan accuse réception / refuse	✅
Levée de réserves par particulier	✅
Réserves majeures → pause chantier	✅
Litige → arbitrage → résolution	✅
Annulation avant 1er jalon (95% remboursé)	✅
Buffer 10% retourné à completion	✅
Frais plateforme 2%	✅
Trust Score automatique à la clôture	✅
Opt-in yield Aave V3 (architecture pluggable)	✅

Prochaines étapes

Déploiement Arbitrum Sepolia — configurer .env avec ARBITRUM_SEPOLIA_RPC_URL et ARBITRUM_SEPOLIA_PRIVATE_KEY, puis lancer npx hardhat ignition deploy ignition/modules/TrustBTP.ts --network arbitrumSepolia
Frontend — connecter wagmi/viem aux events et fonctions du vault
Intégration Aave réelle — enregistrer les adresses aToken sur Arbitrum Sepolia dans AaveV3YieldProvider