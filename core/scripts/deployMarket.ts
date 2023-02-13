import { ethers } from "hardhat";

async function main() {

  const Market = await ethers.getContractFactory("Market");
  const ERC20Mock = await ethers.getContractFactory("ERC20Mock");
  const ERC721Mock = await ethers.getContractFactory("ERC721Mock");

  const market = await Market.deploy();
  const erc721Mock = await ERC721Mock.deploy();
  const erc20Mock = await ERC20Mock.deploy();

  await market.deployed();
  await erc721Mock.deployed();
  await erc20Mock.deployed();

  console.log('market contract deployed ... ');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
