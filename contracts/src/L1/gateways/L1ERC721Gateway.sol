// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {ERC721HolderUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import {IL2ERC721Gateway} from "../../L2/gateways/IL2ERC721Gateway.sol";
import {IL1ScrollMessenger} from "../IL1ScrollMessenger.sol";
import {IL1ERC721Gateway} from "./IL1ERC721Gateway.sol";

import {ScrollGatewayBase} from "../../libraries/gateway/ScrollGatewayBase.sol";

/// @title L1ERC721Gateway
/// @notice The `L1ERC721Gateway` is used to deposit ERC721 compatible NFT in layer 1 and
/// finalize withdraw the NFTs from layer 2.
/// @dev The deposited NFTs are held in this gateway. On finalizing withdraw, the corresponding
/// NFT will be transfer to the recipient directly.
///
/// This will be changed if we have more specific scenarios.
contract L1ERC721Gateway is OwnableUpgradeable, ERC721HolderUpgradeable, ScrollGatewayBase, IL1ERC721Gateway {
    /**********
     * Events *
     **********/

    /// @notice Emitted when token mapping for ERC721 token is updated.
    /// @param _l1Token The address of ERC721 token in layer 1.
    /// @param _l1Token The address of corresponding ERC721 token in layer 2.
    event UpdateTokenMapping(address _l1Token, address _l2Token);

    /*************
     * Variables *
     *************/

    /// @notice Mapping from l1 token address to l2 token address for ERC721 NFT.
    mapping(address => address) public tokenMapping;

    /***************
     * Constructor *
     ***************/

    /// @notice Initialize the storage of L1ERC721Gateway.
    /// @param _counterpart The address of L2ERC721Gateway in L2.
    /// @param _messenger The address of L1ScrollMessenger.
    function initialize(address _counterpart, address _messenger) external initializer {
        OwnableUpgradeable.__Ownable_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();

        ScrollGatewayBase._initialize(_counterpart, address(0), _messenger);
    }

    /*****************************
     * Public Mutating Functions *
     *****************************/

    /// @inheritdoc IL1ERC721Gateway
    function depositERC721(
        address _token,
        uint256 _tokenId,
        uint256 _gasLimit
    ) external payable override {
        _depositERC721(_token, msg.sender, _tokenId, _gasLimit);
    }

    /// @inheritdoc IL1ERC721Gateway
    function depositERC721(
        address _token,
        address _to,
        uint256 _tokenId,
        uint256 _gasLimit
    ) external payable override {
        _depositERC721(_token, _to, _tokenId, _gasLimit);
    }

    /// @inheritdoc IL1ERC721Gateway
    function batchDepositERC721(
        address _token,
        uint256[] calldata _tokenIds,
        uint256 _gasLimit
    ) external payable override {
        _batchDepositERC721(_token, msg.sender, _tokenIds, _gasLimit);
    }

    /// @inheritdoc IL1ERC721Gateway
    function batchDepositERC721(
        address _token,
        address _to,
        uint256[] calldata _tokenIds,
        uint256 _gasLimit
    ) external payable override {
        _batchDepositERC721(_token, _to, _tokenIds, _gasLimit);
    }

    /// @inheritdoc IL1ERC721Gateway
    function finalizeWithdrawERC721(
        address _l1Token,
        address _l2Token,
        address _from,
        address _to,
        uint256 _tokenId
    ) external virtual onlyCallByCounterpart nonReentrant {
        require(_l2Token != address(0), "token address cannot be 0");
        require(_l2Token == tokenMapping[_l1Token], "l2 token mismatch");

        IERC721Upgradeable(_l1Token).safeTransferFrom(address(this), _to, _tokenId);

        emit FinalizeWithdrawERC721(_l1Token, _l2Token, _from, _to, _tokenId);
    }

    /// @inheritdoc IL1ERC721Gateway
    function finalizeBatchWithdrawERC721(
        address _l1Token,
        address _l2Token,
        address _from,
        address _to,
        uint256[] calldata _tokenIds
    ) external virtual onlyCallByCounterpart nonReentrant {
        require(_l2Token != address(0), "token address cannot be 0");
        require(_l2Token == tokenMapping[_l1Token], "l2 token mismatch");

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            IERC721Upgradeable(_l1Token).safeTransferFrom(address(this), _to, _tokenIds[i]);
        }

        emit FinalizeBatchWithdrawERC721(_l1Token, _l2Token, _from, _to, _tokenIds);
    }

    /************************
     * Restricted Functions *
     ************************/

    /// @notice Update layer 2 to layer 2 token mapping.
    /// @param _l1Token The address of ERC721 token in layer 1.
    /// @param _l1Token The address of corresponding ERC721 token in layer 2.
    function updateTokenMapping(address _l1Token, address _l2Token) external onlyOwner {
        require(_l2Token != address(0), "token address cannot be 0");

        tokenMapping[_l1Token] = _l2Token;

        emit UpdateTokenMapping(_l1Token, _l2Token);
    }

    /**********************
     * Internal Functions *
     **********************/

    /// @dev Internal function to deposit ERC721 NFT to layer 2.
    /// @param _token The address of ERC721 NFT in layer 1.
    /// @param _to The address of recipient in layer 2.
    /// @param _tokenId The token id to deposit.
    /// @param _gasLimit Estimated gas limit required to complete the deposit on layer 2.
    function _depositERC721(
        address _token,
        address _to,
        uint256 _tokenId,
        uint256 _gasLimit
    ) internal virtual nonReentrant {
        address _l2Token = tokenMapping[_token];
        require(_l2Token != address(0), "no corresponding l2 token");

        // 1. transfer token to this contract
        IERC721Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _tokenId);

        // 2. Generate message passed to L2ERC721Gateway.
        bytes memory _message = abi.encodeWithSelector(
            IL2ERC721Gateway.finalizeDepositERC721.selector,
            _token,
            _l2Token,
            msg.sender,
            _to,
            _tokenId
        );

        // 3. Send message to L1ScrollMessenger.
        IL1ScrollMessenger(messenger).sendMessage{value: msg.value}(counterpart, 0, _message, _gasLimit, msg.sender);

        emit DepositERC721(_token, _l2Token, msg.sender, _to, _tokenId);
    }

    /// @dev Internal function to batch deposit ERC721 NFT to layer 2.
    /// @param _token The address of ERC721 NFT in layer 1.
    /// @param _to The address of recipient in layer 2.
    /// @param _tokenIds The list of token ids to deposit.
    /// @param _gasLimit Estimated gas limit required to complete the deposit on layer 2.
    function _batchDepositERC721(
        address _token,
        address _to,
        uint256[] calldata _tokenIds,
        uint256 _gasLimit
    ) internal virtual nonReentrant {
        require(_tokenIds.length > 0, "no token to deposit");

        address _l2Token = tokenMapping[_token];
        require(_l2Token != address(0), "no corresponding l2 token");

        // 1. transfer token to this contract
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            IERC721Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _tokenIds[i]);
        }

        // 2. Generate message passed to L2ERC721Gateway.
        bytes memory _message = abi.encodeWithSelector(
            IL2ERC721Gateway.finalizeBatchDepositERC721.selector,
            _token,
            _l2Token,
            msg.sender,
            _to,
            _tokenIds
        );

        // 3. Send message to L1ScrollMessenger.
        IL1ScrollMessenger(messenger).sendMessage{value: msg.value}(counterpart, 0, _message, _gasLimit, msg.sender);

        emit BatchDepositERC721(_token, _l2Token, msg.sender, _to, _tokenIds);
    }
}
