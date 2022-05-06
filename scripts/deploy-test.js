const hre = require("hardhat");

async function main() {
	const XOXO = await hre.ethers.getContractFactory("XOXO");
	const xoxo = await XOXO.deploy();

	await xoxo.deployed();

	console.log("XOXO deployed to:", xoxo.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
	.then(() => process.exit(0))
	.catch((error) => {
		console.error(error);
		process.exit(1);
	});
