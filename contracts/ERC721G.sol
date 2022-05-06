// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

error IncorrectOwner();
error NonexistentToken();
error QueryForZeroAddress();

error TokenIdStaked();
error TokenIdUnstaked();
error ExceedsStakingLimit();

error MintToZeroAddress();
error MintZeroQuantity();
error MintMaxSupplyReached();
error MintMaxWalletReached();

error CallerNotOwnerNorApproved();
error CallerNotOwner();

error ApprovalToCaller();
error ApproveToCurrentOwner();

error TransferFromIncorrectOwner();
error TransferToNonERC721ReceiverImplementer();
error TransferToZeroAddress();

error InvalidTokenType();
error TokenInGame();

abstract contract ERC721G {
    using Address for address;
    using Strings for uint256;

    event Transfer(
        address indexed from,
        address indexed to,
        uint256 indexed id
    );
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 indexed id
    );
    event ApprovalForAll(
        address indexed owner,
        address indexed operator,
        bool approved
    );

    struct TokenData {
        address owner;
        uint40 playStart;
        uint16 wins;
        uint16 loses;
        uint8 XorO;
        bool inPlay;
        bool nextTokenDataSet;
    }

    struct UserData {
        uint40 balance;
        uint40 numMinted;
        uint40 numInPlay;
    }

    string public name;
    string public symbol;

    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    //uint256 public totalSupply;
    uint256 public supplyX;
    uint256 public supplyO;

    uint256 immutable startingIndex;
    uint256 immutable collectionSize;
    uint256 immutable maxPerWallet;

    mapping(uint256 => TokenData) internal _tokenData;
    mapping(address => UserData) internal _userData;

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 startingIndex_,
        uint256 collectionSize_,
        uint256 maxPerWallet_
    ) {
        name = name_;
        symbol = symbol_;
        collectionSize = collectionSize_;
        maxPerWallet = maxPerWallet_;
        startingIndex = startingIndex_;
    }

    /* ------------- Internal ------------- */

    function _mint(
        address to,
        uint256 quantity,
        uint256 _type
    ) internal {
        unchecked {
            uint256 supply;
            if (_type == 0) {
                supply = supplyX;
            } else {
                supply = supplyO;
            }
            uint256 startTokenId = startingIndex + supplyX + supplyO;

            UserData memory userData = _userData[to];

            if (to == address(0)) revert MintToZeroAddress();
            if (quantity == 0) revert MintZeroQuantity();
            if (_type > 1) revert InvalidTokenType();

            if (supply + quantity > collectionSize)
                revert MintMaxSupplyReached();
            if (
                userData.numMinted + quantity > maxPerWallet &&
                address(this).code.length != 0
            ) revert MintMaxWalletReached();

            // don't update for airdrops
            if (to == msg.sender) userData.numMinted += uint40(quantity);

            // don't have to care about next token data if only minting one
            // could optimize to implicitly flag last token id of batch
            // if (quantity == 1) tokenData.nextTokenDataSet = true;
            TokenData memory tokenData = TokenData(
                to,
                uint40(0),
                uint16(0),
                uint16(0),
                uint8(_type),
                false,
                quantity == 1
            );

            userData.balance += uint40(quantity);
            for (uint256 i; i < quantity; ++i)
                emit Transfer(address(0), to, startTokenId + i);

            _userData[to] = userData;
            _tokenData[startTokenId] = tokenData;

            if (_type == 0) {
                supplyX += quantity;
            } else {
                supplyO += quantity;
            }
        }
    }

    // public in case other contracts want to check some of the data on-chain
    function _tokenDataOf(uint256 tokenId)
        public
        view
        returns (TokenData memory tokenData)
    {
        if (!_exists(tokenId)) revert NonexistentToken();

        for (uint256 curr = tokenId; ; curr--) {
            tokenData = _tokenData[curr];
            if (tokenData.owner != address(0)) {
                if (tokenId == curr) return tokenData;
                tokenData.inPlay = false;
                return tokenData;
            }
        }
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        return
            startingIndex <= tokenId && tokenId < startingIndex + totalSupply();
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public {
        TokenData memory tokenData = _tokenDataOf(tokenId);
        address owner = tokenData.owner;

        bool isApprovedOrOwner = (msg.sender == owner ||
            isApprovedForAll[owner][msg.sender] ||
            getApproved[tokenId] == msg.sender);

        if (!isApprovedOrOwner) revert CallerNotOwnerNorApproved();
        if (to == address(0)) revert TransferToZeroAddress();
        if (owner != from) revert TransferFromIncorrectOwner();
        if (tokenData.inPlay) revert TokenInGame();

        delete getApproved[tokenId];

        unchecked {
            if (
                !tokenData.nextTokenDataSet &&
                _tokenData[tokenId + 1].owner == address(0) &&
                _exists(tokenId)
            ) {
                _tokenData[tokenId] = tokenData;
            }

            tokenData.nextTokenDataSet = true;
            tokenData.owner = to;

            _tokenData[tokenId] = tokenData;
        }

        _userData[from].balance--;
        _userData[to].balance++;

        emit Transfer(from, to, tokenId);
    }

    /* ------------- View ------------- */

    function ownerOf(uint256 tokenId) external view returns (address) {
        TokenData memory tokenData = _tokenDataOf(tokenId);
        return tokenData.inPlay ? address(this) : tokenData.owner;
    }

    function trueOwnerOf(uint256 tokenId) external view returns (address) {
        return _tokenDataOf(tokenId).owner;
    }

    function balanceOf(address owner) external view returns (uint256) {
        if (owner == address(0)) revert QueryForZeroAddress();
        return _userData[owner].balance;
    }

    function numInPlay(address user) external view returns (uint256) {
        return _userData[user].numInPlay;
    }

    function numOwned(address user) external view returns (uint256) {
        UserData memory userData = _userData[user];
        return userData.balance + userData.numInPlay;
    }

    function numMinted(address user) external view returns (uint256) {
        return _userData[user].numMinted;
    }

    function totalSupply() public view returns (uint256) {
        return supplyX + supplyO;
    }

    function totalSupplyXandO() public view returns (uint256, uint256) {
        return (supplyX, supplyO);
    }

    // O(N) read-only functions
    // type 0 -> Balance in the users wallet
    // type 1 -> The amount of tokens in play
    // type 2 -> wallet balance + in play tokens balance
    function tokenIdsOf(address user, uint256 type_)
        external
        view
        returns (uint256[] memory)
    {
        unchecked {
            uint256 numTotal = type_ == 0 ? this.balanceOf(user) : type_ == 1
                ? this.numInPlay(user)
                : this.numOwned(user);

            uint256[] memory ids = new uint256[](numTotal);

            if (numTotal == 0) return ids;

            uint256 count;
            TokenData memory tokenData;
            for (
                uint256 i = startingIndex;
                i < totalSupply() + startingIndex;
                ++i
            ) {
                tokenData = _tokenDataOf(i);
                if (user == tokenData.owner) {
                    if (
                        (type_ == 0 && !tokenData.inPlay) ||
                        (type_ == 1 && tokenData.inPlay) ||
                        type_ == 2
                    ) {
                        ids[count++] = i;
                        if (numTotal == count) return ids;
                    }
                }
            }

            return ids;
        }
    }

    function totalNumInPlay() external view returns (uint256) {
        unchecked {
            uint256 count;
            for (
                uint256 i = startingIndex;
                i < startingIndex + totalSupply();
                ++i
            ) {
                if (_tokenDataOf(i).inPlay) ++count;
            }
            return count;
        }
    }

    /* ------------- ERC721 ------------- */

    function tokenURI(uint256 id) public view virtual returns (string memory);

    function supportsInterface(bytes4 interfaceId)
        external
        view
        virtual
        returns (bool)
    {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }

    function approve(address spender, uint256 tokenId) external {
        TokenData memory tokenData = _tokenDataOf(tokenId);
        address owner = tokenData.owner;

        if (
            (msg.sender != owner && !isApprovedForAll[owner][msg.sender]) ||
            tokenData.inPlay
        ) revert CallerNotOwnerNorApproved();

        getApproved[tokenId] = spender;
        emit Approval(owner, spender, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public {
        transferFrom(from, to, tokenId);
        if (
            to.code.length != 0 &&
            IERC721Receiver(to).onERC721Received(
                msg.sender,
                from,
                tokenId,
                data
            ) !=
            IERC721Receiver(to).onERC721Received.selector
        ) revert TransferToNonERC721ReceiverImplementer();
    }
}

interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 id,
        bytes calldata data
    ) external returns (bytes4);
}
