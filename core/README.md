# Sample Hardhat Project


Try running some of the following tasks:

```shell
npx hardhat help
npx hardhat test
REPORT_GAS=true npx hardhat test
npx hardhat node
npx hardhat run scripts/deploy.ts
```

workflow:
基本流程:

1. buyer 发布 购买订单
2. seller 同意 交易，完成转移 token 和 nft 




未考虑: 
1. support ERC1155, batch swap, 
2. sellerSig should include uuid
3. take: 如果此 NFT 以 ERC20 代币交易， 则买方必须批准此合约卖方必须作为运营商 "setApprovalForAll" 此合约
4. 未考虑: fee



