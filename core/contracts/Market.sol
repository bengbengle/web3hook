// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract Market is Context, Ownable, IERC721Receiver, ReentrancyGuard {
    using SafeERC20 for IERC20;

    //default, order no exist
    enum OrderStatus{NOT_EXIST, OPEN, CANCELED, FINISHED, EXPIRE}
    struct TransactionInput {
        uint256 orderUuid; //order_uuid
        address seller;
        address nftAddress;
        uint256 tokenId;
        address erc20Address;
        uint256 price;
        //deadline?
        OrderStatus status;
    }

    struct OrderDetail {
        address seller;
        address buyer;
        address nftAddress;
        uint256 tokenId;
        address erc20Address;
        uint256 price;
        OrderStatus status;
    }

    // BNB or ETH
    address private constant NATIVE_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint32 public constant PCT_FEE_BASE = 1e6;
    uint32 public constant DEFAULT_FEE_PCT = 3 * 1e4; // 3%, 30000=0.03*PCT_FEE_BASE

    bool public _isMarketPaused = false; // default market open
    uint32 public _feePct = DEFAULT_FEE_PCT; //pct: percent
    // signer
    // address private _validator;
    // address private _cfo;

    // nftAddress is added to the market or not
    mapping(address => bool) private _nftAvailable;
    // erc20Address is available or not
    mapping(address => bool) private _erc20Available;
    
    // orderUuid => OrderDetail
    // mapping(uint256 => OrderDetail) private _historyOrders;
    // uint private _historyOrderCount = 0; //Need ?

    event Buy(uint256 orderUuid);
    event CancelOrder(uint256 indexed orderUuid);

    constructor(address validator) {
        _erc20Available[NATIVE_ADDRESS] = true;
        // _cfo = cfo;
        // _validator = validator;
    }

    modifier marketNotPaused() {
        require(!_isMarketPaused, "market is paused now, try later");
        _;
    }

    // function setCFOAddress(address _newCFO) public onlyOwner {
    //     require(_newCFO != address(0));
    //     _cfo = _newCFO;
    // }

    // function getCFOAddress() public view returns (address) {
    //     return _cfo;
    // }

    function pauseMarket(bool isPause) external onlyOwner {
        _isMarketPaused = isPause;
    }

    function setFee(uint32 newFeePct) external onlyOwner {
        //DEFAULT_FEE_PCT = 3 * 1e4; // 3%: 0.03 * PCT_FEE_BASE =30000
        _feePct = newFeePct;
    }

    // function setValidator(address newValidator) external onlyOwner {
    //     _validator = newValidator;
    // }

    function setAvailableNft(address nftAddress, bool newState)
        external
        onlyOwner
    {
        _nftAvailable[nftAddress] = newState;
    }

    function setAvailableERC20(address erc20Address, bool newState)
        external
        onlyOwner
    {
        _erc20Available[erc20Address] = newState;
    }

    //why not direct transfer out?
    function withdraw(address payable to) external onlyOwner {
        //withdraw amount? leave some gas
        uint256 balance = address(this).balance;
        to.transfer(balance);
    }

    //No need withdrawERC20?
    function withdrawERC20(address erc20Address, address to)
        external
        onlyOwner
    {
        IERC20 erc20Token = IERC20(erc20Address);
        uint256 balance = erc20Token.balanceOf(address(this));
        erc20Token.safeTransfer(to, balance);
    }

    // recover
    function withdrawERC721(
        address nftAddress,
        uint256 tokenId,
        address to
    ) external onlyOwner {
        IERC721 nft = IERC721(nftAddress);
        require(
            nft.ownerOf(tokenId) == address(this),
            "this contract is not the owner"
        );
        nft.safeTransferFrom(address(this), to, tokenId);
    }

    //TODO: add ERC1155 support
    function isNftAvailable(address nftAddress) public view returns (bool) {
        return _nftAvailable[nftAddress];
    }

    function isERC20Support(address erc20Address) public view returns (bool) {
        return _erc20Available[erc20Address];
    }

    /**
        if orderUuid not exist in _historyDetail, should return Detail with all zero
        WARNING: caller should check the result is exist or not
     */
    // function getHistoryOrder(uint256 orderUuid) public view returns (OrderDetail memory)
    // {
    //     return _historyOrders[orderUuid];
    // }

    function isOrderOpen(OrderStatus status) public pure returns (bool) {
        return status == OrderStatus.OPEN;
    }

    function isOrderFinal(OrderStatus status) public pure returns (bool) {
        return status == OrderStatus.CANCELED || status == OrderStatus.FINISHED;
    }

    /**
    1, input status == OPEN
    2, order_history Not exist
    3, Gas free order: every exist order should be final status
    4, For auction: order_history status = OPEN
    */
    function isOrderBuyable(
        uint256 orderUuid, 
        OrderStatus inputStatus
    )
        public
        view
        returns (bool)
    {
        // OrderStatus status = _historyOrders[orderUuid].status;

        return inputStatus == OrderStatus.OPEN;
        // && (status == OrderStatus.NOT_EXIST || isOrderOpen(status))
    }

    /**
        For gas free order, order uuid not exist.
        For Auction order, order status==open
    */
    // function isOrderCancelable(uint256 orderUuid) 
    // public view returns (bool)
    // {
    //     // OrderStatus status = _historyOrders[orderUuid].status;
    //     // return status == OrderStatus.NOT_EXIST || status == OrderStatus.OPEN;
    // }

    /**
        FIXME: sellerSig should include uuid
        TODO: add ERC1155 support
        if this NFT traded by ERC20 token, buyer must be approve to this contract
        Seller must "setApprovalForAll" this contract as the operator
     */
    function buy(
        TransactionInput calldata input,
        bytes calldata sellerSig
        // bytes calldata validatorSig
    ) public payable nonReentrant marketNotPaused {
        
        checkOrderValide(
            input, 
            sellerSig
            // validatorSig
        );

        swap(input);
        
        // logHistory(input);

        emit Buy(input.orderUuid);
    }

    function checkOrderValide(
        TransactionInput memory input, 
        bytes memory sellerSig
        // bytes memory validatorSig
    ) 
    internal view {
        uint256 orderUuid = input.orderUuid;
        //TODO: check other input params
        //TODO: check deadline, if order expire, set to expire status
        //if block.timestamp > input.deadline
        //set order.status = expire
        // require(input.deadline >= block.timestamp);
        require(
            isOrderBuyable(orderUuid, input.status),
            "Invalid: orderUuid is not buyable"
        );

        require(
            _nftAvailable[input.nftAddress], "Invalid: this NFT address is not available"
        );
        require(
            _erc20Available[input.erc20Address], "Invalid: this erc20 token is not available"
        );
        
        IERC721 nft = IERC721(input.nftAddress);
        address currentOwner = nft.ownerOf(input.tokenId);
        require(_msgSender() != currentOwner, "owner can not be the buyer"); // let it be?

        // check validator signature
        // bytes32 validatorHash = keccak256(
        //     abi.encodePacked(
        //         orderUuid,
        //         input.seller,
        //         input.nftAddress,
        //         input.tokenId,
        //         input.erc20Address,
        //         input.price
        //     )
        // );
        // checkSignature(validatorSig, validatorHash, _validator, "validator signature error");

        // check seller signature
        bytes32 sellerHash = keccak256(
            abi.encodePacked(
                input.seller,
                input.nftAddress,
                input.tokenId,
                input.erc20Address,
                input.price,
                input.status
            )
        );
        checkSignature(sellerSig, ECDSA.toEthSignedMessageHash(sellerHash), currentOwner, "seller signature error");
    }

    function swap(
        TransactionInput memory input
    ) internal {
        //do payment
        _transferToken(input.price, input.erc20Address, input.seller, _msgSender());
        //do transfer nft
        IERC721 nft = IERC721(input.nftAddress);
        nft.safeTransferFrom(input.seller, _msgSender(), input.tokenId);
    }

    // function logHistory(TransactionInput memory input) internal {
    //     _historyOrders[input.orderUuid] = OrderDetail({
    //         seller: input.seller,
    //         buyer: _msgSender(),
    //         nftAddress: input.nftAddress,
    //         tokenId: input.tokenId,
    //         erc20Address: input.erc20Address,
    //         price: input.price,
    //         status: OrderStatus.FINISHED
    //     });
    // }

    /**
    FIXME: sellerSig should include uuid
    TODO: onlyOwnerOfToken?
    */
    function cancelOrder(
        TransactionInput calldata input,
        bytes calldata sellerSig
    ) public nonReentrant marketNotPaused {

        // require(isOrderCancelable(input.orderUuid), "Invalid: orderUuid is not open");

        IERC721 nft = IERC721(input.nftAddress);
        address currentOwner = nft.ownerOf(input.tokenId);
        require(
            _msgSender() == currentOwner,
            "msg.sender must be the current owner"
        );
        require(_msgSender() == input.seller, "msg.sender must be the seller");

        // check seller signature
        bytes32 sellerHash = keccak256(
            abi.encodePacked(
                input.seller,
                input.nftAddress,
                input.tokenId,
                input.erc20Address,
                input.price,
                input.status
            )
        );
        
        checkSignature(
            sellerSig, 
            ECDSA.toEthSignedMessageHash(sellerHash), 
            currentOwner, 
            "seller signature error"
        );

        //Need Save the other Orderdetail, if not exist?
        // _historyOrders[input.orderUuid].status = OrderStatus.CANCELED;

        emit CancelOrder(input.orderUuid);
    }

    // function isSignatureValid(
    //     bytes memory signature,
    //     bytes32 hashCode,
    //     address signer
    // ) public pure returns (bool) {
    //     address recoveredSigner = ECDSA.recover(hashCode, signature);
    //     return signer == recoveredSigner;
    // }
    function checkSignature(bytes memory signature, bytes32 hashCode, address signer, string memory words)
    public pure {
        require (ECDSA.recover(hashCode, signature) == signer, words);
    }

    function _transferToken(
        uint256 totalPayment,
        address erc20Address,
        address seller,
        address buyer
    ) internal {
        uint256 totalFee = (totalPayment * _feePct) / PCT_FEE_BASE;
        uint256 remaining = totalPayment - totalFee;
        if (erc20Address == NATIVE_ADDRESS) {
            // BNB payment
            //BNB/ETH will pay first to contract address, pay remaining to seller,
            //left totalFee to contract address
            require(
                msg.value >= totalPayment,
                "not enough ETH/BNB balance to buy"
            );
            payable(seller).transfer(remaining);
        } else {
            // ERC20 token payment
            IERC20 erc20Token = IERC20(erc20Address);
            require(
                erc20Token.balanceOf(buyer) >= totalPayment,
                "not enough ERC20 token balance to buy"
            );
            erc20Token.safeTransferFrom(buyer, seller, remaining);
            erc20Token.safeTransferFrom(buyer, address(this), totalFee);
        }
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
