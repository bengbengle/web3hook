let tokenAddress = "0x2A65D41dbC6E8925bD9253abfAdaFab98eA53E34";
let toAddress = "0x8Df70546681657D6FFE227aB51662e5b6e831B7A";
// Use BigNumber
let decimals = web3.toBigNumber(18);
let amount = web3.toBigNumber(100);
let minABI = [
  // transfer
  {
    "constant": false,
    "inputs": [
      {
        "name": "_to",
        "type": "address"
      },
      {
        "name": "_value",
        "type": "uint256"
      }
    ],
    "name": "transfer",
    "outputs": [
      {
        "name": "",
        "type": "bool"
      }
    ],
    "type": "function"
  }
];
// Get ERC20 Token contract instance
let contract = web3.eth.contract(minABI).at(tokenAddress);
// calculate ERC20 token amount
let value = amount.times(web3.toBigNumber(10).pow(decimals));
// call transfer function
contract.transfer(toAddress, value, (error, txHash) => {
  // it returns tx hash because sending tx
  console.log(txHash);
});