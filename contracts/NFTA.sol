//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "hardhat/console.sol";

contract NFTA is ERC721A, Ownable, ReentrancyGuard {
    using ECDSA for bytes32;
    using Strings for uint256;

    enum SaleState {
        PAUSED,
        PRESALE,
        PUBLIC
    }

    SaleState saleState;

    // For Merkle Trees
    bytes32 public merkleRoot;
    // For signatures
    address public allowListSigningAddress =
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    uint256 public immutable maxSupply;
    uint256 public immutable totalReserved;
    uint256 public immutable maxMint;
    uint256 public immutable teamMaxMint;
    uint256 public priceWL;
    uint256 public pricePS;
    uint256 public revealTime;
    string public baseURI;
    string public unrevealedURI;
    address public withdrawalAddress;

    uint256 public WLSaleStart;
    uint256 public publicSaleStart;

    mapping(address => uint256) minted;
    mapping(address => uint256) wlMinted;
    mapping(address => bool) team;
    mapping(address => uint256) teamMinted;

    constructor(
        uint256 _maxSupply,
        uint256 _totalReserved,
        uint256 _maxMint,
        uint256 _teamMaxMint,
        uint256 _priceWL,
        uint256 _pricePS,
        address _withdrawalAddress,
        uint256 _batchSize
    ) ERC721A("NFTA", "NFTA") {
        maxSupply = _maxSupply;
        totalReserved = _totalReserved;
        maxMint = _maxMint;
        teamMaxMint = _teamMaxMint;
        priceWL = _priceWL;
        pricePS = _pricePS;
        withdrawalAddress = _withdrawalAddress;
    }

    // --------- USER API ----------

    function mint(uint256 quantity)
        external
        payable
        callerIsUser
        verifyPrice(quantity, pricePS)
        verifySaleTime(publicSaleStart) // In case the project only needs sale state, this can be removed
        verifySaleState(SaleState.PUBLIC) // In case the project only needs sale time, this can be replaced by pausable
        mintLimit(quantity)
        supplyLimit(quantity, totalReserved)
    {
        _safeMint(msg.sender, quantity);
        refundIfOver(pricePS * quantity);
    }

    function MintSignature(bytes calldata _signature, uint256 quantity)
        external
        payable
        callerIsUser
        verifyPrice(quantity, priceWL)
        verifySignature(_signature)
        verifySaleTime(WLSaleStart) // In case the project only needs sale state, this can be removed
        verifySaleState(SaleState.PRESALE) // In case the project only needs sale time, this can be replaced by pausable
        mintLimit(quantity)
        WLMintLimit(quantity, 5)
        supplyLimit(quantity, totalReserved)
    {
        wlMinted[msg.sender] += quantity;
        _safeMint(msg.sender, quantity);
        refundIfOver(priceWL);
    }

    function WLMintMerkle(bytes32[] calldata merkleProof, uint256 quantity)
        external
        payable
        callerIsUser
        verifyPrice(quantity, priceWL)
        verifyMerkle(merkleProof)
        verifySaleTime(WLSaleStart) // In case the project only needs sale state, this can be removed
        verifySaleState(SaleState.PRESALE) // In case the project only needs sale time, this can be replaced by pausable
        mintLimit(quantity)
        WLMintLimit(quantity, 5)
        supplyLimit(quantity, totalReserved)
    {
        wlMinted[msg.sender] += quantity;
        _safeMint(msg.sender, quantity);
        refundIfOver(priceWL);
    }

    // --------- VIEW --------------

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory uri)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        if (block.timestamp >= revealTime) {
            return
                bytes(baseURI).length > 0
                    ? string(
                        abi.encodePacked(baseURI, tokenId.toString(), ".json")
                    )
                    : unrevealedURI;
        } else {
            return unrevealedURI;
        }
    }

    // TESTING FUNCTION - REMOVE IN PRODUCTION
    function isValidSignature(bytes calldata _signature)
        public
        view
        returns (address)
    {
        bytes32 msgHash = keccak256(abi.encode(address(this), msg.sender));
        return msgHash.toEthSignedMessageHash().recover(_signature);
    }

    // --------- INTERNAL ----------

    // --------- PRIVATE -----------

    function refundIfOver(uint256 price) private {
        require(msg.value >= price, "Need to send more ETH.");
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
    }

    // --------- RESTRICTED -----------

    function teamMint(uint256 quantity)
        external
        payable
        callerIsUser
        teamMintLimit(quantity, 5)
        supplyLimit(quantity, 0)
        onlyTeam
    {
        teamMinted[msg.sender] += quantity;
        _safeMint(msg.sender, quantity);
    }

    function airdropMint(address[] calldata users, uint256 quantity)
        external
        callerIsUser
        supplyLimit(quantity * users.length, 0)
        onlyTeam
    {
        for (uint256 i; i < users.length; i++) {
            _safeMint(users[i], quantity);
        }
    }

    function setBaseURI(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }

    function setUnrevealedURI(string memory _uri) external onlyOwner {
        unrevealedURI = _uri;
    }

    // If reveal is done purely by adding the baseURI, this is unnecessary.
    function setRevealTime(uint256 _revealTime) external onlyOwner {
        revealTime = _revealTime;
    }

    // Both saleStart can be removed if the contract uses only saleStates
    function setPublicSaleStart(uint256 _publicSaleStart) external onlyOwner {
        publicSaleStart = _publicSaleStart;
    }

    function setWLSaleStart(uint256 _WLSaleStart) external onlyOwner {
        WLSaleStart = _WLSaleStart;
    }

    // saleState can be removed if the contract uses only saleTimes. WARNING: Pausible should be added in that case.
    function setSaleState(uint256 _saleState) external onlyOwner {
        saleState = SaleState(_saleState);
    }

    function withdraw() external onlyOwner {
        // Using call because transfer doesn't work with contract addresses, and call works with both accounts and contracts.
        (bool os, ) = payable(withdrawalAddress).call{
            value: address(this).balance
        }("");
        require(os);
    }

    function recoverToken(IERC20 _token) external onlyOwner {
        uint256 balance = _token.balanceOf(address(this));
        bool _success = _token.transfer(owner(), balance);
        require(_success, "Token could not be transferred");
    }

    // --------- MODIFIERS ----------

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "CALLER_IS_CONTRACT");
        _;
    }

    modifier verifySignature(bytes calldata _signature) {
        require(
            allowListSigningAddress ==
                keccak256(
                    abi.encodePacked(
                        "\x19Ethereum Signed Message:\n32",
                        bytes32(uint256(uint160(msg.sender)))
                    )
                ).recover(_signature),
            "not allowed"
        );
        _;
    }

    modifier verifyMerkle(bytes32[] calldata merkleProof) {
        require(
            MerkleProof.verify(
                merkleProof,
                merkleRoot,
                keccak256(abi.encodePacked(msg.sender))
            ),
            "not allowed"
        );
        _;
    }

    modifier verifyPrice(uint256 quantity, uint256 price) {
        require(msg.value >= quantity * price, "PRICE: VALUE_TOO_LOW");
        _;
    }

    modifier verifySaleTime(uint256 saleStart) {
        require(block.timestamp >= saleStart, "SALE_NOT_STARTED");
        _;
    }

    modifier verifySaleState(SaleState _state) {
        require(saleState == _state, "WRONG_SALE_STATE");
        _;
    }

    modifier mintLimit(uint256 quantity) {
        require(
            _numberMinted(msg.sender) + quantity <= maxMint,
            "MAX_MINT: AMOUNT_TOO_HIGH"
        );
        _;
    }

    modifier teamMintLimit(uint256 quantity, uint256 limit) {
        require(
            teamMinted[msg.sender] + quantity <= limit,
            "MAX_MINT: AMOUNT_TOO_HIGH"
        );
        _;
    }

    modifier WLMintLimit(uint256 quantity, uint256 limit) {
        require(
            wlMinted[msg.sender] + quantity <= limit,
            "MAX_MINT: AMOUNT_TOO_HIGH"
        );
        _;
    }

    modifier supplyLimit(uint256 quantity, uint256 reserved) {
        require(
            totalSupply() + quantity <= maxSupply,
            "MAX_SUPPLY: AMOUNT_TOO_HIGH"
        );
        _;
    }

    modifier onlyTeam() {
        require(team[msg.sender], "NOT_IN_TEAM");
        _;
    }
}
