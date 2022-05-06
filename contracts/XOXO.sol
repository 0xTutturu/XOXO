//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ERC721G.sol";

import "hardhat/console.sol";

error GameAlreadyStarted();
error InvalidGameId();
error MaxMintReached();
error MaxSupplyReached();
error WrongTokenType();
error MintLimitReached();

contract XOXO is ERC721G, Ownable, ReentrancyGuard {
    mapping(uint256 => uint256) public tokensAndGames;
    mapping(address => uint256) public minted;

    uint256 internal currentGameId;
    uint256 public typeMaxSupply = 1500;
    uint256 public lockupPeriod = 1 days;

    // PlayerTurn -> (0) Player 1, (1) Player 2
    // gameState -> if the game is ongoing or not. (00) ongoing, (01) player 1 win, (11) player 2 win, (01) draw
    // tokenX and tokenO are the token IDs in play
    // [gameStartTimestamp][gameData][gameState][PlayerTurn][tokenTwo][tokenOne]
    // [0000000000000000000000000000000000000000][000000000000000000][00][0][0000000000000000][0000000000000000]

    constructor() ERC721G("XOXO", "XOXO", 1, 3000, 2) {}

    /* User interaction */

    function mint(uint256 _quantity, uint256 _type)
        external
        payable
        nonReentrant
    {
        if (_type == 0 && supplyX + _quantity > typeMaxSupply)
            revert MaxSupplyReached();
        if (_type == 1 && supplyO + _quantity > typeMaxSupply)
            revert MaxSupplyReached();
        _mint(msg.sender, _quantity, _type);
    }

    function createNewGame(uint256 _tokenId) external {
        TokenData memory tokenData = _tokenDataOf(_tokenId);
        if (tokenData.owner != msg.sender) revert CallerNotOwner();
        if (tokenData.inPlay) revert TokenInGame();
        uint256 gameId = currentGameId++;

        uint256 game = _tokenId | uint256(block.timestamp << 53);
        _tokenData[_tokenId].inPlay = true;
        tokensAndGames[gameId] = game;
    }

    function joinGame(uint256 _gameId, uint256 _tokenId) external {
        uint256 game = tokensAndGames[_gameId];
        uint16 tokenOne = uint16(game);
        TokenData memory tokenDataOne = _tokenDataOf(tokenOne);
        TokenData memory tokenDataTwo = _tokenDataOf(_tokenId);

        if (_gameId >= currentGameId) revert InvalidGameId();
        if (uint16(tokensAndGames[_gameId] >> 16) != 0)
            revert GameAlreadyStarted();
        if (tokenDataTwo.inPlay) revert TokenInGame();
        if (tokenDataTwo.owner != msg.sender) revert CallerNotOwner();
        if (tokenDataTwo.XorO == tokenDataOne.XorO) revert WrongTokenType();
        if (tokenDataOne.owner == tokenDataTwo.owner) revert(); // Can't play with yourself
        _tokenData[_tokenId].inPlay = true;
        tokensAndGames[_gameId] |= (_tokenId << 16);
    }

    function endGame(uint256 _gameId, uint256 _tokenId) external {
        uint256 game = tokensAndGames[_gameId];
        uint256 gameState = checkGameState(game >> 32);
        TokenData memory tokenData = _tokenDataOf(_tokenId);
        uint16 tokenOne = uint16(game);
        uint16 tokenTwo = uint16(game >> 16);
        uint40 gameStartedAt = uint40(game >> 53);

        if (tokenOne != _tokenId && tokenTwo != _tokenId) revert(); // must be one of the tokens in play
        if (tokenData.owner != msg.sender) revert(); // Only owner of tokenId can do it
        if (block.timestamp - gameStartedAt < lockupPeriod) revert(); // Prevent lock up of tokens
        if (gameState != 0) revert(); // Game is already over

        tokensAndGames[_gameId] = (((game >> 33) & 0x00) | 1) | game;
    }

    function playMove(uint256 _gameId, uint256 _index) external {
        uint256 game = tokensAndGames[_gameId];
        uint256 inMemGame = game >> 32;
        uint16 tokenOne = uint16(game);
        uint16 tokenTwo = uint16(game >> 16);
        uint256 tokens = uint256(uint32(game));
        TokenData memory tokenDataOne = _tokenDataOf(tokenOne);
        TokenData memory tokenDataTwo = _tokenDataOf(tokenTwo);

        require(
            (msg.sender == tokenDataOne.owner && inMemGame & 1 == 0) ||
                (msg.sender == tokenDataTwo.owner && inMemGame & 1 == 1),
            "NOT_YOUR_TURN"
        );
        require((inMemGame >> 1) & 3 == 0);
        require(_index < 9, "Invalid_move");
        require(((inMemGame >> 3) >> (_index << 1)) & 3 == 0);

        // Already checked above so could remove the second else and just do one if/else
        if ((msg.sender == tokenDataOne.owner && inMemGame & 1 == 0)) {
            inMemGame |= 1;
            inMemGame |=
                (((inMemGame >> 3) >> (_index << 1)) | 1) <<
                ((_index << 1) + 3);
        } else {
            inMemGame &= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE;
            inMemGame |=
                (((inMemGame >> 3) >> (_index << 1)) | 3) <<
                ((_index << 1) + 3);
        }

        uint256 state = checkGameState(inMemGame);

        if (state == 2) {
            tokenDataTwo.wins += 1;
            tokenDataTwo.inPlay = false;

            tokenDataOne.loses += 1;
            tokenDataOne.XorO = tokenDataTwo.XorO;
            tokenDataOne.inPlay = false;

            _tokenData[tokenOne] = tokenDataOne;
            _tokenData[tokenTwo] = tokenDataTwo;
            tokensAndGames[_gameId] |= ((inMemGame | 6) << 32);
        } else if (state == 1) {
            tokenDataOne.wins += 1;
            tokenDataOne.inPlay = false;

            tokenDataTwo.loses += 1;
            tokenDataTwo.XorO = tokenDataOne.XorO;
            tokenDataTwo.inPlay = false;

            _tokenData[tokenOne] = tokenDataOne;
            _tokenData[tokenTwo] = tokenDataTwo;
            tokensAndGames[_gameId] |= ((inMemGame | 4) << 32);
        } else {
            tokensAndGames[_gameId] = (inMemGame << 32) | tokens;
        }
    }

    /* View */

    function getAllGames() external view returns (uint256[] memory) {
        uint256[] memory games = new uint256[](currentGameId);
        for (uint256 i; i < currentGameId; i++) {
            games[i] = tokensAndGames[i];
        }
        return games;
    }

    function getTokensInPlay(uint256 _gameId)
        external
        view
        returns (uint16, uint16)
    {
        uint256 game = tokensAndGames[_gameId];

        uint16 tokenOne = uint16(game);
        uint16 tokenTwo = uint16(game >> 16);

        return (tokenOne, tokenTwo);
    }

    function getTimestamp(uint256 _gameId) external view returns (uint256) {
        return uint40(tokensAndGames[_gameId] >> 56);
    }

    function getBoard(uint256 _gameId) external view returns (uint256) {
        uint256 game = tokensAndGames[_gameId] >> 35;
        return (game & 0x3FFFF);
    }

    function getGame(uint256 _gameId) external view returns (uint256) {
        return tokensAndGames[_gameId];
    }

    function getPlayerTurn(uint256 _gameId) external view returns (uint256) {
        uint256 game = tokensAndGames[_gameId];
        uint256 inMemGame = game >> 32;
        return inMemGame & 1;
    }

    function getWin(uint256 _gameId) external view returns (uint256) {
        uint256 game = tokensAndGames[_gameId] >> 32;
        return checkGameState(game);
    }

    function tokenURI(uint256 _tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        if (!_exists(_tokenId)) revert();
        TokenData memory tokenData = _tokenDataOf(_tokenId);

        if (tokenData.XorO == 0) return "X";
        else return "O";
    }

    /* Internal */

    function checkGameState(uint256 _board) internal pure returns (uint256) {
        _board >>= 4;

        uint256 masks = 0xFC003F00CCC186106187030306184003F;

        uint256 boardShifts = 0x190480;

        while (masks != 0) {
            uint256 mask = masks & 0x3FFFF;
            if (_board & mask == mask) return 2;
            else if (_board & mask == (mask / 3)) return 1;

            _board >>= (boardShifts & 7);
            masks >>= 18;
            boardShifts >>= 3;
        }

        return 0;
    }

    /* Restricted */

    function setLockupPeriod(uint256 _timeDelta) external onlyOwner {
        lockupPeriod = _timeDelta;
    }
}
