// Script for deploying GenesisNFT with upgradeable pattern
// Run with: npx hardhat run deploy.js --network <network>

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // 1. Deploy GenesisNFTLogic implementation contract
  console.log("Deploying implementation contract...");
  const GenesisNFTLogic = await ethers.getContractFactory("GenesisNFTLogic");
  const logic = await GenesisNFTLogic.deploy();
  await logic.deployed();
  console.log("GenesisNFTLogic deployed to:", logic.address);

  // 2. Prepare initialization data
  const defaultAdmin = deployer.address;
  const name = "IKIGAI Genesis";
  const symbol = "IKGNFT";
  const royaltyRecipient = deployer.address;
  const royaltyBps = 500; // 5%
  const beraToken = "0x..."; // Replace with actual BERA token address
  const ikigaiToken = "0x..."; // Replace with actual IKIGAI token address
  const treasuryAddress = "0x..."; // Replace with actual treasury address
  const buybackEngine = "0x..."; // Replace with actual buyback engine address
  const beraHolderPrice = ethers.utils.parseEther("0.1");
  const whitelistPrice = ethers.utils.parseEther("0.15");
  const publicPrice = ethers.utils.parseEther("0.2");

  // 3. Get initialization data
  console.log("Encoding initialization data...");
  const GenesisNFTDeployer = await ethers.getContractFactory("GenesisNFTDeployer");
  const deployer_contract = await GenesisNFTDeployer.deploy();
  await deployer_contract.deployed();
  
  const initData = await deployer_contract.getInitializationData(
    defaultAdmin,
    name,
    symbol,
    royaltyRecipient,
    royaltyBps,
    beraToken,
    ikigaiToken,
    treasuryAddress,
    buybackEngine,
    beraHolderPrice,
    whitelistPrice,
    publicPrice
  );
  
  console.log("Initialization data:", initData);

  // 4. Deploy GenesisNFTProxy
  console.log("Deploying proxy contract...");
  const GenesisNFTProxy = await ethers.getContractFactory("GenesisNFTProxy");
  const proxy = await GenesisNFTProxy.deploy(logic.address, initData);
  await proxy.deployed();
  console.log("GenesisNFTProxy deployed to:", proxy.address);

  // 5. Create contract instance with proxy address but implementation ABI
  console.log("Setting up proxy with implementation ABI...");
  const genesisNFT = GenesisNFTLogic.attach(proxy.address);
  
  // 6. Verify contracts (optional)
  console.log("\nVerification commands:");
  console.log(`npx hardhat verify --network <network> ${logic.address}`);
  console.log(`npx hardhat verify --network <network> ${proxy.address} ${logic.address} ${initData}`);
  
  console.log("\nDeployment completed successfully!");
  console.log("Interact with the contract at:", proxy.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 