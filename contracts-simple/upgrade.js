// Script for upgrading GenesisNFT to V2
// Run with: npx hardhat run upgrade.js --network <network>

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Upgrading contract with the account:", deployer.address);

  // Proxy contract address (already deployed)
  const proxyAddress = "0x..."; // Replace with actual deployed proxy address
  
  // 1. Deploy GenesisNFTLogicV2 implementation
  console.log("Deploying V2 implementation contract...");
  const GenesisNFTLogicV2 = await ethers.getContractFactory("GenesisNFTLogicV2");
  const logicV2 = await GenesisNFTLogicV2.deploy();
  await logicV2.deployed();
  console.log("GenesisNFTLogicV2 deployed to:", logicV2.address);

  // 2. Create contract instance to interact with the proxy
  console.log("Setting up proxy interaction...");
  const genesisNFT = await ethers.getContractAt("GenesisNFTLogic", proxyAddress);
  
  // 3. Check if the caller has the UPGRADE_ROLE
  const UPGRADE_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("UPGRADE_ROLE"));
  const hasRole = await genesisNFT.hasRole(UPGRADE_ROLE, deployer.address);
  if (!hasRole) {
    console.error("The deployer does not have the UPGRADE_ROLE. Cannot upgrade the contract.");
    process.exit(1);
  }
  
  // 4. Upgrade the proxy to the new implementation
  console.log("Upgrading proxy to V2 implementation...");
  // This calls the upgradeTo function from the UUPSUpgradeable contract
  const upgradeTx = await genesisNFT.upgradeTo(logicV2.address);
  await upgradeTx.wait();
  console.log("Proxy upgraded to V2 implementation successfully!");

  // 5. Now the proxy has the V2 implementation, let's initialize the V2 specific features
  console.log("Initializing V2 features...");
  const genesisNFTV2 = await ethers.getContractAt("GenesisNFTLogicV2", proxyAddress);
  
  // Set VIP price and discount percentage
  const vipPrice = ethers.utils.parseEther("0.08");
  const discountPercentage = 300; // 3% discount per NFT held
  
  const initV2Tx = await genesisNFTV2.initializeV2(vipPrice, discountPercentage);
  await initV2Tx.wait();
  console.log("V2 features initialized successfully!");
  
  // 6. Verify new implementation (optional)
  console.log("\nVerification command:");
  console.log(`npx hardhat verify --network <network> ${logicV2.address}`);
  
  console.log("\nUpgrade completed successfully!");
  console.log("The contract at", proxyAddress, "is now using the V2 implementation.");
  console.log("New V2 features are available for use.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 