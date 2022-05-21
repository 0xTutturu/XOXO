//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

contract MockERC721 is ERC721, ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    string _baseTokenURI;
    string[] svgBase = [
        "<svg width='",
        "' height='",
        "' xmlns='http://www.w3.org/2000/svg'><g><text xml:space='preserve' text-anchor='start' font-family='Noto Sans JP' font-size='100' id='svg_1' y='",
        "' x='",
        "' stroke-width='",
        "' stroke='",
        "' fill='",
        "'>",
        "</text></g></svg>"
    ];

    constructor() ERC721("mock", "mock") {
        setBaseURI("data:image/svg+xml;base64,");
        _tokenIds.increment(); //token ids start from 1
    }

    function createCollectible(uint256 _amount) public {
        for (uint256 i; i < _amount; i++) {
            mint(msg.sender);
        }
    }

    function mint(address _user) internal {
        uint256 newItemId = _tokenIds.current();
        _safeMint(_user, newItemId);
        setTokenURI(newItemId);
        _tokenIds.increment();
    }

    /* Converts an SVG to Base64 string */
    function svgToImageURI() public pure returns (string memory) {
        string memory baseURL = "data:image/svg+xml;base64,";
        string
            memory _svg = "<svg width='800' height='600' xmlns='http://www.w3.org/2000/svg'><g><title>Layer 1</title><text xml:space='preserve' text-anchor='start' font-family='Noto Sans JP' font-size='100' id='svg_1' y='305.5' x='345' stroke-width='0' stroke='#000' fill='#000000'>x</text></g></svg>";
        string memory svgBase64Encoded = Base64.encode(bytes(_svg));
        return string(abi.encodePacked(baseURL, svgBase64Encoded));
    }

    // width, height, yPosition, xPosition, strokeWidth, strokeColor, fillColor, text
    function dynamicSVG(string[] calldata data)
        public
        view
        returns (string memory)
    {
        string memory image;
        string memory baseURL = "data:image/svg+xml;base64,";
        for (uint256 i; i < svgBase.length; i++) {
            if (i == data.length) {
                image = string(abi.encodePacked(image, svgBase[i]));
            } else {
                image = string(abi.encodePacked(image, svgBase[i], data[i]));
            }
        }
        string memory svgBase64Encoded = Base64.encode(bytes(image));
        return string(abi.encodePacked(baseURL, svgBase64Encoded));
    }

    /* Generates a tokenURI using Base64 string as the image */
    function formatTokenURI(string memory imageURI)
        public
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
                                '{"name": "LCM ON-CHAINED", "description": "A simple SVG based on-chain NFT", "image":"',
                                imageURI,
                                '"}'
                            )
                        )
                    )
                )
            );
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string memory baseURI) public onlyOwner {
        _baseTokenURI = baseURI;
    }

    function getTokenCount() public view returns (uint256) {
        return _tokenIds.current();
    }

    function setTokenURI(uint256 _tokenId) internal {
        string memory newURI = string(
            abi.encodePacked(_baseTokenURI, _tokenId)
        );
        _setTokenURI(_tokenId, newURI);
    }

    // The following functions are overrides required by Solidity.

    function _burn(uint256 tokenId)
        internal
        override(ERC721, ERC721URIStorage)
    {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }
}
