//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

import "./ERC721G.sol";
import "./libraries/SVG.sol";
import "./libraries/Utils.sol";

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
            tokenDataTwo.totalPlayed += 1;
            tokenDataTwo.inPlay = false;
            /* tokenDataTwo.scoreHistory = _newScore(
                tokenDataTwo.scoreHistory,
                tokenDataTwo.totalPlayed,
                3
            ); */
            tokenDataTwo.scoreHistory = _newScore(tokenDataTwo, 3);

            tokenDataOne.totalPlayed += 1;
            tokenDataOne.XorO = tokenDataTwo.XorO;
            tokenDataOne.inPlay = false;
            /* tokenDataOne.scoreHistory = _newScore(
                tokenDataOne.scoreHistory,
                tokenDataOne.totalPlayed,
                1
            ); */
            tokenDataOne.scoreHistory = _newScore(tokenDataOne, 1);

            _tokenData[tokenOne] = tokenDataOne;
            _tokenData[tokenTwo] = tokenDataTwo;
            tokensAndGames[_gameId] |= ((inMemGame | 6) << 32);
        } else if (state == 1) {
            tokenDataOne.totalPlayed += 1;
            tokenDataOne.inPlay = false;
            /* tokenDataOne.scoreHistory = _newScore(
                tokenDataOne.scoreHistory,
                tokenDataOne.totalPlayed,
                3
            ); */
            tokenDataOne.scoreHistory = _newScore(tokenDataOne, 3);

            tokenDataTwo.totalPlayed += 1;
            tokenDataTwo.XorO = tokenDataOne.XorO;
            tokenDataTwo.inPlay = false;
            /* tokenDataTwo.scoreHistory = _newScore(
                tokenDataTwo.scoreHistory,
                tokenDataTwo.totalPlayed,
                1
            ); */
            tokenDataTwo.scoreHistory = _newScore(tokenDataTwo, 1);

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

        return _formatTokenURI(getImage(_tokenId));
    }

    /* Internal */

    function checkGameState(uint256 _board) public pure returns (uint256) {
        _board >>= 3;

        uint256 masks = 0xFC003F00CCC30C30C30F03030C30C003F; //0xFC003F00CCC186106187030306184003F;
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

    function _newScore(TokenData memory tokenData, uint256 _winOrLoss)
        internal
        pure
        returns (uint256[] memory)
    {
        uint256 _totalPlayed = tokenData.totalPlayed;
        uint256 index = _totalPlayed / 128;
        uint256 position = (_totalPlayed - 1) % 128;
        uint256[] memory changedScore = new uint256[](index + 1);

        for (uint256 i; i < tokenData.scoreHistory.length; i++) {
            changedScore[i] = tokenData.scoreHistory[i];
        }
        if (tokenData.scoreHistory.length < index + 1) {
            uint256 score;
            score |= _winOrLoss << (position << 1);
            changedScore[index] = score;
        }
        return changedScore;
    }

    /*  // 1 is loss, 3 is win
    function _newScore(
        uint256[] memory _score,
        uint256 _totalPlayed,
        uint256 _winOrLoss
    ) internal pure returns (uint256[] memory) {
        uint256 index = _totalPlayed / 128;
        uint256 position = (_totalPlayed - 1) % 128;
        uint256[] memory newScore = new uint256[](index + 1);
        newScore = _score;
        // same as multiplied by two
        newScore[index] |= _winOrLoss << (position << 1);
        return newScore;
    } */

    function getImage(uint256 _tokenId) public view returns (string memory) {
        if (!_exists(_tokenId)) revert();
        TokenData memory tokenData = _tokenDataOf(_tokenId);

        uint256[] memory _score = tokenData.scoreHistory;
        uint256 totalPlayed = tokenData.totalPlayed;
        uint8 _type = tokenData.XorO;

        string
            memory image = '<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1000" style="background:#9061F9;border-style:solid;border-color:white;">';
        string memory typeText = _type == 0 ? "X" : "O";

        for (uint256 i; i < totalPlayed; i++) {
            uint256 index = totalPlayed / 128;
            uint256 position = i % 128;
            uint256 result = (_score[index] >> (position << 1)) & 3;
            uint256 xPosition = (i % 24) * 40 + 10;
            uint256 yPosition = (i / 24) * 50 + 50;
            string memory xOrO = result == 1 ? "O" : "X";

            image = string.concat(
                image,
                svg.text(
                    string.concat(
                        svg.prop("x", utils.uint2str(xPosition)),
                        svg.prop("y", utils.uint2str(yPosition)),
                        svg.prop("font-size", "70"),
                        svg.prop("fill", "black")
                    ),
                    string.concat(svg.cdata(xOrO))
                )
            );
        }
        image = string.concat(
            image,
            svg.text(
                string.concat(
                    svg.prop("x", "280"),
                    svg.prop("y", "700"),
                    svg.prop("font-size", "600"),
                    svg.prop("fill", "white")
                ),
                string.concat(svg.cdata(typeText))
            ),
            "</svg>"
        );

        string memory baseURL = "data:image/svg+xml;base64,";
        string memory svgBase64Encoded = Base64.encode(bytes(image));
        string memory base64Image = string(
            abi.encodePacked(baseURL, svgBase64Encoded)
        );

        return base64Image;
    }

    function _formatTokenURI(string memory imageURI)
        internal
        pure
        returns (string memory)
    {
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name": "XOXO", "description": "On chain Tic-Tac-Toe war game.", "image":"',
                                imageURI,
                                '"}'
                            )
                        )
                    )
                )
            );
    }

    /* Restricted */

    function setLockupPeriod(uint256 _timeDelta) external onlyOwner {
        lockupPeriod = _timeDelta;
    }
}
