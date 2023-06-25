// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "lib/sstore2/contracts/SSTORE2.sol";
import "lib/solady/src/utils/LibString.sol";
import {Base64} from "lib/solady/src/utils/Base64.sol";
import {Color, LibColor, newColorFromRGB, newColorFromRGBString} from "lib/solcolor/src/Color.sol";

contract JB721StakingUriResolver {
    using LibString for string;
    using LibString for uint256;
    using LibColor for Color;

    address immutable SVG_TEMPLATE_POINTER;
    address immutable SVG_TEMPLATE_INDICES_POINTER;

    string constant REPLACEMENT_OPEN_SYMBOL = "!!{";
    string constant REPLACEMENT_CLOSE_SYMBOL = "}";

    string constant GRADIENT_COLOR_A = "COLOR_A";
    string constant GRADIENT_COLOR_B = "COLOR_B";
    string constant GRADIENT_COLOR_C = "COLOR_C";
    string constant TEXT_COLOR = "TEXT_COLOR";
    string constant TEXT_SECTION = "TEXT_SECTION";

        
    //*********************************************************************//
    // -------------------- private constant properties ------------------ //
    //*********************************************************************//
    uint256 private constant _ONE_BILLION = 1_000_000_000;


    // Configuration for the SVG
    uint256 private constant _SHOW_DECIMAL_AMOUNT_BELOW = 10;
    uint256 private constant _ROUND_TO = 10 ** 15;

    constructor(address _svgTemplatePointer) {
        // Store the pointer to the template
        SVG_TEMPLATE_POINTER = _svgTemplatePointer;
        // Load the template
        string memory _template = _loadTemplate();
        // Calculate where we will need to replace occurances in `tokenUri`
        uint256[] memory _indices = _template.indicesOf(
            REPLACEMENT_OPEN_SYMBOL
        );
        // Store them
        SVG_TEMPLATE_INDICES_POINTER = SSTORE2.write(bytes(abi.encode(_indices)));
    }

    function tokenUri(uint256 tokenId) external view returns (string memory) {
        string memory _template = _loadTemplate();

        // Perform your template manipulations
        Color[3] memory _colors = _getColorsForTier(tokenId);

        uint256[] memory _indices = _template.indicesOf(
            REPLACEMENT_OPEN_SYMBOL
        );

        int256 _bytesDiff;
        for (uint256 _i = 0; _i < _indices.length; _i++) {
            uint256 _newLocation = uint256(int256(_indices[_i]) + _bytesDiff);
            
            uint256 _closeLocation = _template.indexOf(
                REPLACEMENT_CLOSE_SYMBOL,
                _newLocation + bytes(REPLACEMENT_OPEN_SYMBOL).length
            );
            string memory _identifier = _template.slice(
                _newLocation + bytes(REPLACEMENT_OPEN_SYMBOL).length,
                _closeLocation
            );

            if (_identifier.eq(GRADIENT_COLOR_A)) {
                int256 _diff;
                (_template, _diff) = _replaceInTemplate(
                    _template,
                    _colors[0].toString(),
                    _newLocation,
                    _closeLocation + bytes(REPLACEMENT_CLOSE_SYMBOL).length
                );
                _bytesDiff += _diff;
                continue;
            }

            if (_identifier.eq(GRADIENT_COLOR_B)) {
                int256 _diff;
                (_template, _diff) = _replaceInTemplate(
                    _template,
                    _colors[1].toString(),
                    _newLocation,
                    _closeLocation + bytes(REPLACEMENT_CLOSE_SYMBOL).length
                );

                _bytesDiff += _diff;
                continue;
            }

            if (_identifier.eq(GRADIENT_COLOR_C)) {
                int256 _diff;
                (_template, _diff) = _replaceInTemplate(
                    _template,
                    _colors[2].toString(),
                    _newLocation,
                    _closeLocation + bytes(REPLACEMENT_CLOSE_SYMBOL).length
                );

                _bytesDiff += _diff;
                continue;
            }
            
            if (_identifier.eq(TEXT_COLOR)) {
                int256 _diff;
                (_template, _diff) = _replaceInTemplate(
                    _template,
                    _determineBestTextColorForContrast(_colors[2]),
                    _newLocation,
                    _closeLocation + bytes(REPLACEMENT_CLOSE_SYMBOL).length
                );

                _bytesDiff += _diff;
                continue;
            }

            if (_identifier.eq(TEXT_SECTION)) {
                int256 _diff;
                (_template, _diff) = _replaceInTemplate(
                    _template,
                    _getSVGText(tokenId),
                    _newLocation,
                    _closeLocation + bytes(REPLACEMENT_CLOSE_SYMBOL).length
                );

                _bytesDiff += _diff;
                continue;
            }
        }

        return _buildTokenUriResponse(_template);
    }

    

    function _determineBestTextColorForContrast(
        Color _backgroundColor
    ) internal pure returns (string memory) {
        (uint8 red, uint8 green, uint8 blue) = _backgroundColor.toRGB();
        // TODO change threshold to 150?
        return
            ((uint256(red) * 299) / 1000) +
                ((uint256(green) * 587) / 1000) +
                ((uint256(blue) * 114) / 1000) >
                186
                ? "121212"
                : "f0f0f0";
    }

        function _getSVGText(uint256 tokenId) internal pure returns (string memory) {
        // TODO get these amounts
        uint256 _tier = tierIdOfToken(tokenId);
        uint256 _stakedAmount = 8.05 ether + 2005111000000;

        return string.concat(
            '<text x="40" y="635" font-size="28">Tier ', _tier.toString() ,'</text>',
            '<text x="45" y="660" font-size="14">', _getNumberInUnits(_stakedAmount, 18, _ROUND_TO) ,' NANA</text>'
        );
    }

    function _getNumberInUnits(uint256 _size, uint256 _decimals, uint256 _roundTo) internal pure returns (string memory) {
        uint256 _oneUnit = 10 ** _decimals;
        
        // Get the number of full units
        uint256 _fullUnits = _size / _oneUnit;
        
        if(_size < _SHOW_DECIMAL_AMOUNT_BELOW * _oneUnit) {
            uint256 _decimalAmount = _size - _fullUnits * _oneUnit;
            return string.concat(_fullUnits.toString(), _getStringDecimalNumber(_decimalAmount, _decimals, _roundTo));
        }

        string memory _rawNumber = _fullUnits.toString();
        uint256 _rawNumberSize = bytes(_rawNumber).length;

        // If its more than 1000 we comma divide the number
        if(_rawNumberSize >= 4){
            uint256 _seperators = (_rawNumberSize - 1) / 3;
            bytes memory _prettyNumber = new bytes(_rawNumberSize + _seperators);

            uint256 _posInPretty = _prettyNumber.length - 1;
            for (uint256 _i = 0; _i < _rawNumberSize; _i++) {
                if(_i % 3 == 0 && _posInPretty != 0 && _i != 0) {
                    _prettyNumber[_posInPretty] = bytes1(0x2c);
                    --_posInPretty;
                }
                _prettyNumber[_posInPretty] = bytes(_rawNumber)[_rawNumberSize - _i - 1];
                if (_posInPretty != 0) --_posInPretty;
            }

            return string(_prettyNumber);
        }

        return _rawNumber;
    }

    /**
     * @param _amountBelowDecimal the amount thats below the decimal (behind the decimal point)
     * @param _decimals the decimal amount we should use
     */
    function _getStringDecimalNumber(uint256 _amountBelowDecimal, uint256 _decimals, uint256 _roundTo) internal pure returns (string memory) {
        // Round the number
        _amountBelowDecimal = _amountBelowDecimal - (_amountBelowDecimal % _roundTo);

        string memory _number = _amountBelowDecimal.toString();
        // These are all numbers, so they all take a single byte
        // First we left-pad the number so its at the correct location
        while(bytes(_number).length < _decimals) {
            _number = string.concat("0", _number);
        }
        // Then we find how many right padded numbers there are
        uint256 _highestNonZero = bytes(_number).length - 1;
        while(_highestNonZero > 0) {
            if (bytes(_number)[_highestNonZero] != bytes1("0")) break;
            _highestNonZero--;
        }
        // Create a substring up to where the right padded numbers start
        bytes memory _finalString = new bytes(_highestNonZero + 1);
        for (uint256 _i = 0; _i <= _highestNonZero; _i++) {
            _finalString[_i] = bytes(_number)[_i];
        }

        return string.concat(".", string(_finalString));
    }



    function _getColorsForTier(
        uint256 _tierId
    ) internal pure returns (Color[3] memory _colors) {
        bytes32 _hash = keccak256(abi.encodePacked(_tierId));
        _colors[0] = newColorFromRGB(bytes3(_hash));
        _colors[1] = newColorFromRGB(bytes3(_hash << 3));
        _colors[2] = newColorFromRGB(bytes3(_hash << 6));
    }


    /**
     * @notice
     * The tier number of the provided token ID.
     *
     * @dev Tier's are 1 indexed from the `tiers` array, meaning the 0th element of the array is tier 1.
     *
     * @param _tokenId The ID of the token to get the tier number of.
     *
     * @return The tier number of the specified token ID.
     */
    function tierIdOfToken(uint256 _tokenId) public pure returns (uint256) {
        return _tokenId / _ONE_BILLION;
    }

    function _loadTemplate() internal virtual view returns (string memory) {
        return string(SSTORE2.read(SVG_TEMPLATE_POINTER));
    }

    function _replaceInTemplate(
        string memory _template,
        string memory _replacement,
        uint256 _replaceFrom,
        uint256 _replaceTo
    ) internal pure returns (string memory _newTemplate, int256 _bytesDiff) {
        _newTemplate = string.concat(
            _template.slice(0, _replaceFrom),
            _replacement,
            _template.slice(_replaceTo, bytes(_template).length)
        );

        return (
            _newTemplate,
            int256(bytes(_replacement).length) - int256(_replaceTo - _replaceFrom)
        );
    }

    function _buildTokenUriResponse(string memory _svg) internal pure returns (string memory) {
        string memory _metadata = string(
            abi.encodePacked(
                '{"name":"XYZ",',
                '"description":"Description Text",',
                '"image":"data:image/svg+xml;base64,'
            )
        );

        return string.concat(
            "data:application/json;base64,",
            Base64.encode(abi.encodePacked(_metadata, Base64.encode(bytes(_svg), true, true), '"}'), true, true)
        );
    }
}
