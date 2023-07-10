// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IJBPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import {IJBPayoutRedemptionPaymentTerminal3_1_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayoutRedemptionPaymentTerminal3_1_1.sol";
import {IJBFundingCycleBallot} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import {IJBOperatable} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatable.sol";
import {IJBSplitAllocator} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitAllocator.sol";
import {IJBToken} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBToken.sol";
import {IJBFundingCycleDataSource3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleDataSource3_1_1.sol";
import {JBOperations} from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBOperations.sol";
import {JBConstants} from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBConstants.sol";
import {JBSplitsGroups} from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBSplitsGroups.sol";
import {JBFundingCycleData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleData.sol";
import {JBFundingCycleMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import {JBFundingCycle} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycle.sol";
import {JBPayDelegateAllocation3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayDelegateAllocation3_1_1.sol";
import {JBRedemptionDelegateAllocation3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedemptionDelegateAllocation3_1_1.sol";
import {JBPayParamsData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayParamsData.sol";
import {JBRedeemParamsData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedeemParamsData.sol";
import {JBGlobalFundingCycleMetadata} from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGlobalFundingCycleMetadata.sol";
import {JBGroupedSplits} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGroupedSplits.sol";
import {JBSplit} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplit.sol";
import {JBOperatorData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBOperatorData.sol";
import {JBFundAccessConstraints} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundAccessConstraints.sol";
import {JBProjectMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol";
import {BasicRetailistJBParams, BasicRetailistJBDeployer} from "./BasicRetailistJBDeployer.sol";

/// @notice A contract that facilitates deploying a basic Retailist treasury that also calls other pay delegates that are specified when the project is deployed.
contract PayAllocatorRetailistJBDeployer is BasicRetailistJBDeployer, IJBFundingCycleDataSource3_1_1 {
    /// @notice The data source that returns the correct values for the Buyback Delegate of each project.
    /// @custom:param projectId The ID of the project to which the Buyback Delegate allocations apply.
    mapping(uint256 => IJBFundingCycleDataSource3_1_1) public buybackDelegateDataSourceOf;

    /// @notice The delegate allocations to include during payments to projects.
    /// @custom:param projectId The ID of the project to which the delegate allocations apply.
    mapping(uint256 => JBPayDelegateAllocation3_1_1[]) public delegateAllocationsOf;

    /// @notice This function gets called when the project receives a payment.
    /// @dev Part of IJBFundingCycleDataSource.
    /// @dev This implementation just sets this contract up to receive a `didPay` call.
    /// @param _data The Juicebox standard project payment data. See https://docs.juicebox.money/dev/api/data-structures/jbpayparamsdata/.
    /// @return weight The weight that project tokens should get minted relative to. This is useful for optionally customizing how many tokens are issued per payment.
    /// @return memo A memo to be forwarded to the event. Useful for describing any new actions that are being taken.
    /// @return delegateAllocations Amount to be sent to delegates instead of adding to local balance. Useful for auto-routing funds from a treasury as payment come in.
    function payParams(JBPayParamsData calldata _data)
        external
        view
        virtual
        override
        returns (uint256 weight, string memory memo, JBPayDelegateAllocation3_1_1[] memory delegateAllocations)
    {
        // Keep a reference to the delegate allocatios that the Buyback Data Source provides.
        JBPayDelegateAllocation3_1_1[] memory _buybackDelegateAllocations;

        // Set the values to be those returned by the Buyback Data Source.
        (weight, memo, _buybackDelegateAllocations) = buybackDelegateDataSourceOf[_data.projectId].payParams(_data);

        // Cache the delegate allocations.
        JBPayDelegateAllocation3_1_1[] memory _delegateAllocations = delegateAllocationsOf[_data.projectId];

        // Keep a reference to the number of delegate allocations;
        uint256 _numberOfDelegateAllocations = _delegateAllocations.length;

        // Each delegate allocation must run, plus the buyback delegate.
        delegateAllocations = new JBPayDelegateAllocation3_1_1[](_numberOfDelegateAllocations + 1);

        // All the rest of the delegate allocations the project expects.
        for (uint256 _i; _i < _numberOfDelegateAllocations; ) {
          delegateAllocations[_i] = _delegateAllocations[_i];
          unchecked {
            ++_i;
          }
        }

        // Add the buyback delegate as the last element.
        delegateAllocations[_numberOfDelegateAllocations] = _buybackDelegateAllocations[0];
    }

    /// @notice This function is never called, it needs to be included to adhere to the interface.
    function redeemParams(JBRedeemParamsData calldata _data)
        external
        view
        virtual
        override
        returns (uint256, string memory, JBRedemptionDelegateAllocation3_1_1[] memory)
    {
      _data; // Unused.
      return (0, '', new JBRedemptionDelegateAllocation3_1_1[](0));
    }

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param _interfaceId The ID of the interface to check for adherence to.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4 _interfaceId) public view virtual override(BasicRetailistJBDeployer, IERC165) returns (bool) {
        return _interfaceId == type(IJBFundingCycleDataSource3_1_1).interfaceId || super.supportsInterface(_interfaceId);
    }

    /// @param _controller The controller that projects are made from.
    /// @param _terminal The terminal that projects use to accept payments from.
    constructor(IJBController3_1 _controller, IJBPayoutRedemptionPaymentTerminal3_1_1 _terminal) BasicRetailistJBDeployer(_controller, _terminal) {}

    /// @notice Deploy a project with basic Retailism constraints.
    /// @param _operator The address that will receive the token premint, initial reserved token allocations, and who is allowed to change the allocated reserved rate distribution.
    /// @param _projectMetadata The metadata containing project info.
    /// @param _name The name of the ERC-20 token being create for the project.
    /// @param _symbol The symbol of the ERC-20 token being created for the project.
    /// @param _data The data needed to deploy a basic retailist project.
    /// @param _delegateAllocations Any pay delegate allocations that should run when the project is paid.
    /// @return projectId The ID of the newly created Retailist project.
    function deployProjectFor(
        address _operator,
        JBProjectMetadata memory _projectMetadata,
        string memory _name,
        string memory _symbol,
        BasicRetailistJBParams calldata _data,
        JBPayDelegateAllocation3_1_1[] calldata _delegateAllocations
    ) external returns (uint256 projectId) {
        // Package the reserved token splits.
        JBGroupedSplits[] memory _groupedSplits = new JBGroupedSplits[](1);

        // Make the splits.
        {
            // Make a new splits specifying where the reserved tokens will be sent.
            JBSplit[] memory _splits = new JBSplit[](1);

            // Send the _operator all of the reserved tokens. They'll be able to change this later whenever they wish.
            _splits[1] = JBSplit({
                preferClaimed: false,
                preferAddToBalance: false,
                percent: JBConstants.SPLITS_TOTAL_PERCENT,
                projectId: 0,
                beneficiary: payable(_operator),
                lockedUntil: 0,
                allocator: IJBSplitAllocator(address(0))
            });

            _groupedSplits[0] = JBGroupedSplits({group: JBSplitsGroups.RESERVED_TOKENS, splits: _splits});
        }

        // Deploy a project.
        projectId = controller.projects().createFor({
          owner: address(this), // This contract should remain the owner, forever.
          metadata: _projectMetadata
        });

        // Issue the project's ERC-20 token.
        IJBToken _token = controller.tokenStore().issueFor({projectId: projectId, name: _name, symbol: _symbol});

        // TODO: Deploy BBD. 
        address _buybackDelegate = address(0);
        _token;

        // Keep a reference to this data source.
        buybackDelegateDataSourceOf[projectId] = IJBFundingCycleDataSource3_1_1(_buybackDelegate);

        // Configure the project's funding cycles using BBD. 
        controller.launchFundingCyclesFor({
            projectId: projectId,
            data: JBFundingCycleData({
                duration: _data.discountPeriod,
                weight: _data.initialIssuanceRate ** 18,
                discountRate: _data.discountRate,
                ballot: IJBFundingCycleBallot(address(0))
            }),
            metadata: JBFundingCycleMetadata({
                global: JBGlobalFundingCycleMetadata({
                    allowSetTerminals: false,
                    allowSetController: false,
                    pauseTransfers: false
                }),
                reservedRate: _data.reservedRate, // Set the reserved rate.
                redemptionRate: _data.redemptionRate, // Set the redemption rate.
                ballotRedemptionRate: 0, // There will never be an active ballot, so this can be left off.
                pausePay: false,
                pauseDistributions: false, // There will never be distributions accessible anyways.
                pauseRedeem: false, // Redemptions must be left open.
                pauseBurn: false,
                allowMinting: true, // Allow this contract to premint tokens as the project owner.
                allowTerminalMigration: false,
                allowControllerMigration: false,
                holdFees: false,
                preferClaimedTokenOverride: false,
                useTotalOverflowForRedemptions: false,
                useDataSourceForPay: true, // Use the buyback delegate data source.
                useDataSourceForRedeem: false,
                // This contract should be the data source.
                dataSource: address(this),
                metadata: 0
            }),
            mustStartAtOrAfter: 0,
            groupedSplits: _groupedSplits,
            fundAccessConstraints: new JBFundAccessConstraints[](0), // Funds can't be accessed by the project owner.
            terminals: terminals,
            memo: "Deployed Retailist treasury"
        });

        // Premint tokens to the Operator.
        controller.mintTokensOf({
            projectId: projectId,
            tokenCount: _data.premintTokenAmount ** 18,
            beneficiary: _operator,
            memo: string.concat("Preminted ", _symbol, " tokens."),
            preferClaimedTokens: false,
            useReservedRate: false
        });

        // Give the operator permission to change the allocated reserved rate distribution destination.
        IJBOperatable(address(controller.splitsStore())).operatorStore().setOperator(
            JBOperatorData({operator: _operator, domain: projectId, permissionIndexes: permissionIndexes})
        );

        // Store the timestamp after which the project's reconfigurd funding cycles can start. A separate transaction to `scheduledReconfigurationOf` must be called to formally scheduled it.
        reconfigurationStartTimestampOf[projectId] = block.timestamp + _data.reservedRateDuration;

        // Store the pay delegate allocations.
        uint256 _numberOfDelegateAllocations = _delegateAllocations.length;

        for (uint256 _i; _i < _numberOfDelegateAllocations;) {
          delegateAllocationsOf[projectId] [_i] = _delegateAllocations[_i];
          unchecked {
            ++_i;
          }
        }
    }
}