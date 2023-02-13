// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
// pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

using ECDSA for bytes32; 

contract Market is Context, Ownable, IERC721Receiver, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // default, order no exist
    enum Status{NOT_EXIST, OPEN, CANCELED, FINISHED, EXPIRE}

    struct Order {
        uint256 oid; // order_uuid
        address maker;
        address taker;

        address erc721Address;
        uint256 tokenId;

        address erc20Address;
        uint256 amount;

        Status status;
    }

    // BNB or ETH
    address private constant NATIVE_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    bool public _isMarketPaused = false; // default market open

    mapping(address => bool) private _erc721Available;
    mapping(address => bool) private _erc20Available;
    
    event TakeEvent(uint256 oid);

    constructor() {
        _erc20Available[NATIVE_ADDRESS] = true;
    }

    modifier marketNotPaused() {
        require(!_isMarketPaused, "market is paused now, try later");
        _;
    }


    function pauseMarket(bool isPause) external onlyOwner {
        
        _isMarketPaused = isPause;
    }

    function setAvailablERC721(address erc721Address, bool newState) external onlyOwner {

        _erc721Available[erc721Address] = newState;
    }

    function setAvailableERC20(address erc20Address, bool newState) external onlyOwner {

        _erc20Available[erc20Address] = newState;
    }

    function withdraw(address payable to) external onlyOwner {

        uint256 balance = address(this).balance;
        to.transfer(balance);
    }

    // No need withdrawERC20?
    function withdrawERC20(address _address, address to) external onlyOwner {

        IERC20 token = IERC20(_address);
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(to, balance);
    }

    // recover
    function withdrawERC721(address _address, uint256 _tokenId, address to) external onlyOwner {
        
        IERC721 erc721 = IERC721(_address);
        require(
            erc721.ownerOf(_tokenId) == address(this), "this contract is not the owner"
        );
        erc721.safeTransferFrom(address(this), to, _tokenId);
    }


    function isERC721Available(address erc721Address) public view returns (bool) {
        return _erc721Available[erc721Address];
    }

    function isERC20Available(address erc20Address) public view returns (bool) {
        return _erc20Available[erc20Address];
    }


    function isOrderOpen(Status status) public pure returns (bool) {
        return status == Status.OPEN;
    }

    function isOrderFinal(Status status) public pure returns (bool) {
        return status == Status.CANCELED || status == Status.FINISHED;
    }
  
    function hashToVerify(Order memory _order) private pure returns (bytes32){
        return keccak256(
            abi.encodePacked(
                _order.oid,
                _order.maker,
                _order.taker,

                _order.erc721Address,
                _order.tokenId,
                
                _order.erc20Address,
                _order.amount,
                
                _order.status
            )
        );
    }
    

    function verifyOrder(Order memory _order, bytes memory signature) public view  returns(address ,bool) {
        
        require(
            _order.status == Status.OPEN, "Invalid: oid is not tabkeable"
        );

        require(
            _erc721Available[_order.erc721Address], "Invalid: this NFT address is not available"
        );

        require(
            _erc20Available[_order.erc20Address], "Invalid: this erc20 token is not available"
        );

        bytes32 verifyHash = hashToVerify(_order);

        address signerAddress = verifyHash.toEthSignedMessageHash().recover(signature);

        if (_order.maker == signerAddress) {
            //The message is authentic
            return (signerAddress, true);
        } else {
            //msg.sender didnt sign this message.
            return (signerAddress,false);
        }
    }
  

    function take(
        Order calldata _order,
        bytes calldata _sig
    ) public payable nonReentrant marketNotPaused {
        
        // check order isvalide?
        _checkIsValide(_order, _sig);

        // transfer erc20
        _transferERC20(_order.erc20Address, _order.amount, _order.maker, _msgSender());

        // transfer erc721
        _transferERC721(_order.erc721Address, _order.tokenId, _msgSender(),  _order.maker);
        
        // emit event
        emit TakeEvent(_order.oid);
    }

    function _checkIsValide(Order memory _order, bytes memory _sig) internal view {

         require(
            _order.status == Status.OPEN, "Invalid: oid is not tabkeable"
        );

        require(
            _erc721Available[_order.erc721Address], "Invalid: this NFT address is not available"
        );

        require(
            _erc20Available[_order.erc20Address], "Invalid: this erc20 token is not available"
        );

        bytes32 verifyHash = hashToVerify(_order);

        address signerAddress = verifyHash.toEthSignedMessageHash().recover(_sig);

        // if (_order.maker == signerAddress) {
        //     //The message is authentic
        //     return (signerAddress, true);
        // } else {
        //     //msg.sender didnt sign this message.
        //     return (signerAddress,false);
        // }

        require (_order.maker == signerAddress, "maker signature error");
    }

    function _transferERC20(address _erc20Address, uint256 _amount, address _from, address _to) internal {

        if (_erc20Address == NATIVE_ADDRESS) {
           require(
                msg.value >= _amount, "not enough ETH/BNB balance to take"
            );
            payable(_to).transfer(_amount);

        } else {

            IERC20 erc20 = IERC20(_erc20Address);
            require(
                erc20.balanceOf(_from) >= _amount, "not enough ERC20 token balance to take"
            );
            erc20.safeTransferFrom(_from, _to, _amount);
        }
    }

    function _transferERC721(address _erc721, uint256 _tokenId, address _from , address _to) internal {

        IERC721 erc721 = IERC721(_erc721);

        address erc721Owner = erc721.ownerOf(_tokenId);
        require(_from == erc721Owner, "does't has the nft owner");

        erc721.safeTransferFrom(_from, _to, _tokenId);
    }

    /**
     * @dev See {IERC721Receiver-onERC721Received}.
     *
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
