require("@nomiclabs/hardhat-waffle");
require("solidity-coverage");
require("hardhat-contract-sizer");
//require("hardhat-gas-reporter");
require("dotenv").config();

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
	defaultNetwork: "hardhat",
	networks: {
		localhost: {
			url: "http://127.0.0.1:8545",
		},
		hardhat: {},
		ethMain: {
			url: process.env.PROVIDER_MAINNET,
			chainID: 1,
			accounts: [process.env.PRIVATE_KEY1, process.env.PRIVATE_KEY2],
		},
		kovan: {
			url: process.env.PROVIDER_KOVAN,
			chainID: 42,
			accounts: [process.env.PRIVATE_KEY1, process.env.PRIVATE_KEY2],
		},
		rinkeby: {
			url: process.env.PROVIDER_RINKEBY,
			chainID: 4,
			accounts: [process.env.PRIVATE_KEY1, process.env.PRIVATE_KEY2],
		},
		bsc: {
			url: process.env.PROVIDER_BSC,
			chainId: 56,
			accounts: [process.env.PRIVATE_KEY1, process.env.PRIVATE_KEY2],
		},
		bscTest: {
			url: process.env.PROVIDER_BSC_TESTNET,
			chainId: 97,
			gasPrice: 20000000000,
			accounts: [process.env.PRIVATE_KEY1, process.env.PRIVATE_KEY2],
		},
		avalanche: {
			url: process.env.PROVIDER_AVAX,
			chainID: 43114,
			accounts: [process.env.PRIVATE_KEY1, process.env.PRIVATE_KEY2],
		},
		avalancheFuji: {
			url: process.env.PROVIDER_AVAX_TESTNET,
			chainID: 43113,
			accounts: [process.env.PRIVATE_KEY1, process.env.PRIVATE_KEY2],
		},
		polygon: {
			url: process.env.PROVIDER_POLYGON,
			chainID: 136,
			accounts: [process.env.PRIVATE_KEY1, process.env.PRIVATE_KEY2],
		},
		polygonMumbai: {
			url: process.env.PROVIDER_MUMBAI,
			chainID: 80001,
			accounts: [process.env.PRIVATE_KEY1, process.env.PRIVATE_KEY2],
		},
	},
	solidity: {
		version: "0.8.7",
		settings: {
			optimizer: {
				enabled: true,
				runs: 10000,
			},
		},
	},
	paths: {
		sources: "./contracts",
		tests: "./test",
		cache: "./cache",
		artifacts: "./artifacts",
	},
	mocha: {
		timeout: 1000000,
	},
	gasReporter: {
		coinmarketcap: "7c6dba17-dc6a-42db-996b-9587eaffc8e8",
		token: "ETH",
		gasPrice: 100,
		/* token: "BNB",
    gasPrice: 10,
    token: "MATIC",
    gasPrice: 50,
    token: "AVAX",
    gasPrice: 50 */
	},
	etherscan: {
		apiKey: process.env.ETHERSCAN_KEY,
		//apiKey: process.env.BSCSCAN_KEY,
		// apiKey: process.env.SNOWTRACE_KEY,
		//apiKey: process.env.POLYGONSCAN_KEY
	},
};
