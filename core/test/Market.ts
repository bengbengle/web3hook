import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers,network, web3 } from "hardhat";
import { Market } from "../typechain-types/contracts";
// import web3 from  "@nomiclabs/hardhat-web3";

describe("Market", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployMarket() {

    const [maker, taker] = await ethers.getSigners();

    const Market = await ethers.getContractFactory("Market");
    const ERC20Mock = await ethers.getContractFactory("ERC20Mock");
    const ERC721Mock = await ethers.getContractFactory("ERC721Mock");

    const market = await Market.deploy();
    const erc721Mock = await ERC721Mock.deploy();
    const erc20Mock = await ERC20Mock.deploy();

    await market.deployed();
    await erc721Mock.deployed();
    await erc20Mock.deployed();

    await erc20Mock.mint(maker.address, 1000000);
    await erc721Mock.safeMint(maker.address); // 0
    await erc721Mock.safeMint(maker.address); // 1

    await erc721Mock.safeMint(taker.address); // 2
    await erc721Mock.safeMint(taker.address); // 3
    await erc721Mock.safeMint(taker.address); // 4

    await market.setAvailableERC20(erc20Mock.address, true);
    await market.setAvailablERC721(erc721Mock.address, true);

    return { market, erc20Mock, erc721Mock, maker, taker };
  }

  async function signRawOrder(_order: any, seller: string) {
    
    let message = ethers.utils.solidityPack(
      [
        "uint256",  // oid
        "address",  //"maker"
        "address",  //"taker"
        "address",  // erc721
        "uint256",  // tokenId
        "address",  // erc20
        "uint256",  // amount
        "uint8"     // status
      ],
      [
        _order.oid, // order id = new Date().getTime(),  
        _order.maker,
        _order.taker,

        _order.erc721Address,
        _order.tokenId,
        
        _order.erc20Address,
        _order.amount,//price
        _order.status, // de
      ]
    );

    let msghash = ethers.utils.keccak256(message);
    var sig= await web3.eth.sign(msghash, seller);

    return sig;

  }
  describe("Deployment", function () {
    it("Should set the Supported ERC20", async function () {
      const { market, erc20Mock, erc721Mock } = await loadFixture(deployMarket);
      expect(await market.isERC20Available(erc20Mock.address)).to.equal(true);
    });
    it("Should set the Supported ERC721", async function () {
      const { market, erc20Mock, erc721Mock } = await loadFixture(deployMarket);
      expect(await market.isERC721Available(erc721Mock.address)).to.equal(true);
    });

    it("Should maker’s erc721 balance equal 1000000", async function () {
      const { market, erc20Mock, erc721Mock, maker, taker } = await loadFixture(deployMarket);

      expect(await erc20Mock.balanceOf(maker.address)).to.equal(1000000);

      expect(await erc721Mock.balanceOf(maker.address)).to.equal(2);
      expect(await erc721Mock.balanceOf(taker.address)).to.equal(3);
    });
  });


  describe("Maker Sig", function () {

    it("Should the seller sig be passed", async function () {

      const { market, erc20Mock, erc721Mock, maker, taker } = await loadFixture(deployMarket);

      const o = {
        oid: "1",
        maker: maker.address, // use erc20 swap erc721
        taker: taker.address, // use erc721 swap erc20
        erc721Address: erc721Mock.address,
        erc20Address: erc20Mock.address,
        tokenId: "2",
        amount: "100",
        status: "1"
      }

      let sig = await signRawOrder(o, maker.address);
      
      let _isvalid = await market.verifyOrder(o, sig);
      
      console.log('maker::', o.maker);
      console.log('taker::', o.taker);

      console.log('isvalid:', _isvalid);

      expect(_isvalid[0]).to.equal(maker.address);
    });

    

  });

  
  describe("Bid And Accept", function () {

    it("Should buy success", async function () {

      const { market, erc20Mock, erc721Mock, maker, taker } = await loadFixture(deployMarket);

      const o = {
        oid: "1",
        maker: maker.address, // use erc20 swap erc721
        taker: taker.address, // use erc721 swap erc20
        erc721Address: erc721Mock.address,
        erc20Address: erc20Mock.address,
        tokenId: "2",
        amount: "5",
        status: "1"
      }
      // 0. pre check the amount and nft 
      
      expect(await erc20Mock.balanceOf(maker.address)).to.equal(1000000);
      expect(await erc721Mock.balanceOf(maker.address)).to.equal(2);
      
      expect(await erc20Mock.balanceOf(taker.address)).to.equal(0);
      // expect(await erc721Mock.balanceOf(taker.address)).to.equal(3);
      expect(await erc721Mock.ownerOf(2)).to.equal(taker.address);
     


      
      await erc20Mock.connect(maker).approve(market.address,100);
      await erc721Mock.connect(taker).setApprovalForAll(market.address, true);

      // 1. maker sign a buy order
      let sig = await signRawOrder(o, maker.address);
      
      // 2. taker accept the order
      await market.connect(taker).take(o, sig);
      
      // 3. verify the amount and nft
       
      expect(await erc20Mock.balanceOf(maker.address)).to.equal(999995);
      expect(await erc721Mock.balanceOf(maker.address)).to.equal(3);
      
      expect(await erc20Mock.balanceOf(taker.address)).to.equal(5);
      expect(await erc721Mock.balanceOf(taker.address)).to.equal(2);
      
      expect(await erc721Mock.ownerOf(2)).to.equal(maker.address);
    });
  });
});
