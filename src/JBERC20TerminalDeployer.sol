// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {JBERC20PaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/JBERC20PaymentTerminal.sol";
import {IJBDirectory} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import {IJBProjects} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBProjects.sol";
import {IJBOperatorStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";
import {IJBSplitsStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitsStore.sol";
import {IJBPrices} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPrices.sol";
import {IJBSingleTokenPaymentTerminalStore} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminalStore.sol";

/// @notice Deploys new ERC20 payment terminals.
contract JBERC20TerminalDeployer {
    /// @notice Deploys a new JB ERC20 terminal.
    /// @dev The current owner of project 1 will become the owner of the terminal
    /// @param _token The token that this terminal manages.
    /// @param _currency The currency that this terminal's token adheres to for price feeds.
    /// @param _baseWeightCurrency The currency to base token issuance on.
    /// @param _payoutSplitsGroup The group that denotes payout splits from this terminal in the splits store.
    /// @param _operatorStore A contract storing operator assignments.
    /// @param _projects A contract which mints ERC-721's that represent project ownership and transfers.
    /// @param _directory A contract storing directories of terminals and controllers for each project.
    /// @param _splitsStore A contract that stores splits for each project.
    /// @param _prices A contract that exposes price feeds.
    /// @param _store A contract that stores the terminal's data.
    function deploy(
        IERC20Metadata _token,
        uint256 _currency,
        uint256 _baseWeightCurrency,
        uint256 _payoutSplitsGroup,
        IJBOperatorStore _operatorStore,
        IJBProjects _projects,
        IJBDirectory _directory,
        IJBSplitsStore _splitsStore,
        IJBPrices _prices,
        IJBSingleTokenPaymentTerminalStore _store
    ) external returns (IJBPayoutRedemptionPaymentTerminal _terminal) {
        // Deploy a new terminal
        _terminal = new JBERC20PaymentTerminal(
            _token,
            _currency,
            _baseWeightCurrency,
            _payoutSplitsGroup,
            _operatorStore,
            _projects,
            _directory,
            _splitsStore,
            _prices,
            _store,
            address(_projects.ownerOf(1))
        );
    }
}
