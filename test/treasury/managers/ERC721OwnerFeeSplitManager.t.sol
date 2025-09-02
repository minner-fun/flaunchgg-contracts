// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from '@uniswap/v4-core/src/types/PoolId.sol';

import {Flaunch} from '@flaunch/Flaunch.sol';
import {PositionManager} from '@flaunch/PositionManager.sol';
import {FeeSplitManager} from '@flaunch/treasury/managers/FeeSplitManager.sol';
import {ERC721OwnerFeeSplitManager} from '@flaunch/treasury/managers/ERC721OwnerFeeSplitManager.sol';
import {TreasuryManagerFactory} from '@flaunch/treasury/managers/TreasuryManagerFactory.sol';

import {ITreasuryManager} from '@flaunch-interfaces/ITreasuryManager.sol';

import {ERC721Mock} from 'test/mocks/ERC721Mock.sol';
import {FlaunchTest} from 'test/FlaunchTest.sol';


contract ERC721OwnerFeeSplitManagerTest is FlaunchTest {

    // The treasury manager
    ERC721OwnerFeeSplitManager feeSplitManager;
    address managerImplementation;

    bytes constant EMPTY_BYTES = abi.encode('');
    uint public constant MAX_SHARE = 100_00000;

    // Set up some ERC721Mock contracts
    ERC721Mock erc1;
    ERC721Mock erc2;
    ERC721Mock erc3;

    function setUp() public {
        _deployPlatform();

        erc1 = new ERC721Mock('ERC1', '1');
        erc2 = new ERC721Mock('ERC2', '2');
        erc3 = new ERC721Mock('ERC3', '3');

        managerImplementation = address(
            new ERC721OwnerFeeSplitManager(address(treasuryManagerFactory))
        );

        treasuryManagerFactory.approveManager(managerImplementation);
    }

    function test_CanInitializeSuccessfully() public {
        // Set up our revenue split
        ERC721OwnerFeeSplitManager.ERC721Share[] memory recipientShares = new ERC721OwnerFeeSplitManager.ERC721Share[](3);
        recipientShares[0] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc1), 20_00000, 10);
        recipientShares[1] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc2), 50_00000, 10);
        recipientShares[2] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc3), 30_00000, 20);

        // Set up our {TreasuryManagerFactory} and approve our implementation
        _deployWithRecipients(recipientShares, 20_00000, 0);

        (address erc721, uint share, uint totalSupply) = feeSplitManager.erc721Shares(address(erc1));
        assertEq(erc721, address(erc1));
        assertEq(share, 20_00000);
        assertEq(totalSupply, 10);

        (erc721, share, totalSupply) = feeSplitManager.erc721Shares(address(erc2));
        assertEq(erc721, address(erc2));
        assertEq(share, 50_00000);
        assertEq(totalSupply, 10);

        (erc721, share, totalSupply) = feeSplitManager.erc721Shares(address(erc3));
        assertEq(erc721, address(erc3));
        assertEq(share, 30_00000);
        assertEq(totalSupply, 20);

        (erc721, share, totalSupply) = feeSplitManager.erc721Shares(address(1));
        assertEq(erc721, address(0));
        assertEq(share, 0);
        assertEq(totalSupply, 0);
    }

    function test_CannotInitializeWithInvalidCreatorShare(uint _invalidShare) public {
        vm.assume(_invalidShare > MAX_SHARE);

        // Set up our revenue split
        ERC721OwnerFeeSplitManager.ERC721Share[] memory recipientShares = new ERC721OwnerFeeSplitManager.ERC721Share[](2);
        recipientShares[0] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc1), 50_00000, 10);
        recipientShares[1] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc2), 50_00000, 20);

        // Initialize our token
        vm.expectRevert();
        _deployWithRecipients(recipientShares, _invalidShare, 0);
    }

    function test_CannotInitializeWithInvalidOwnerShare(uint _invalidShare) public {
        vm.assume(_invalidShare > MAX_SHARE);

        // Set up our revenue split
        ERC721OwnerFeeSplitManager.ERC721Share[] memory recipientShares = new ERC721OwnerFeeSplitManager.ERC721Share[](2);
        recipientShares[0] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc1), 50_00000, 10);
        recipientShares[1] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc2), 50_00000, 20);

        // Initialize our token
        vm.expectRevert();
        _deployWithRecipients(recipientShares, 0, _invalidShare);
    }

    function test_CannotInitializeWithInvalidCombinedShare(uint _creatorShare, uint _ownerShare) public {
        // Bind our individual shares to be under 100%, but for the combined share to be over 100%
        _creatorShare = bound(_creatorShare, MAX_SHARE / 2 + 1, MAX_SHARE);
        _ownerShare = bound(_ownerShare, MAX_SHARE / 2 + 1, MAX_SHARE);

        // Ensure that the combined share is above 100%
        vm.assume(_creatorShare + _ownerShare > MAX_SHARE);

        // Set up our revenue split
        ERC721OwnerFeeSplitManager.ERC721Share[] memory recipientShares = new ERC721OwnerFeeSplitManager.ERC721Share[](2);
        recipientShares[0] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc1), 50_00000, 10);
        recipientShares[1] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc2), 50_00000, 20);

        // Initialize our token
        vm.expectRevert(abi.encodeWithSelector(FeeSplitManager.InvalidShareTotal.selector));
        _deployWithRecipients(recipientShares, _creatorShare, _ownerShare);
    }

    function test_CannotInitializeWithInvalidShareTotal() public {
        // Set up our revenue split
        ERC721OwnerFeeSplitManager.ERC721Share[] memory recipientShares = new ERC721OwnerFeeSplitManager.ERC721Share[](3);
        recipientShares[0] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc1), 20_00000, 10);
        recipientShares[1] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc2), 40_00000, 10);
        recipientShares[2] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc3), 30_00000, 20);

        // Set up our {TreasuryManagerFactory} and approve our implementation
        vm.expectRevert(abi.encodeWithSelector(
            FeeSplitManager.InvalidRecipientShareTotal.selector,
            90_00000, 100_00000
        ));

        // Initialize our token
        _deployWithRecipients(recipientShares, 20_00000, 0);
    }

    function test_CannotInitializeWithZeroAddressRecipient() public {
        // Set up our revenue split
        ERC721OwnerFeeSplitManager.ERC721Share[] memory recipientShares = new ERC721OwnerFeeSplitManager.ERC721Share[](3);
        recipientShares[0] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc1), 20_00000, 10);
        recipientShares[1] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc2), 50_00000, 10);
        recipientShares[2] = ERC721OwnerFeeSplitManager.ERC721Share(address(0), 30_00000, 20);

        // Set up our {TreasuryManagerFactory} and approve our implementation
        vm.expectRevert(ERC721OwnerFeeSplitManager.InvalidInitializeParams.selector);

        // Initialize our token
        _deployWithRecipients(recipientShares, 20_00000, 0);
    }

    function test_CannotInitializeWithZeroShareRecipient() public {
        // Set up our revenue split
        ERC721OwnerFeeSplitManager.ERC721Share[] memory recipientShares = new ERC721OwnerFeeSplitManager.ERC721Share[](3);
        recipientShares[0] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc1), 20_00000, 10);
        recipientShares[1] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc2), 50_00000, 10);
        recipientShares[2] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc3), 0, 20);

        // Set up our {TreasuryManagerFactory} and approve our implementation
        vm.expectRevert(ERC721OwnerFeeSplitManager.InvalidInitializeParams.selector);

        // Initialize our token
        _deployWithRecipients(recipientShares, 20_00000, 0);
    }

    function test_CannotInitializeWithZeroTotalSupplyRecipient() public {
        // Set up our revenue split
        ERC721OwnerFeeSplitManager.ERC721Share[] memory recipientShares = new ERC721OwnerFeeSplitManager.ERC721Share[](3);
        recipientShares[0] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc1), 20_00000, 0);
        recipientShares[1] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc2), 50_00000, 10);
        recipientShares[2] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc3), 30_00000, 20);

        // Set up our {TreasuryManagerFactory} and approve our implementation
        vm.expectRevert(ERC721OwnerFeeSplitManager.InvalidInitializeParams.selector);

        // Initialize our token
        _deployWithRecipients(recipientShares, 20_00000, 0);
    }

    function test_CanInitializeWithMultipleRecipients() public {
        ERC721OwnerFeeSplitManager.ERC721Share[] memory recipientShares = new ERC721OwnerFeeSplitManager.ERC721Share[](3);
        recipientShares[0] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc1), 20_00000, 10);
        recipientShares[1] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc2), 50_00000, 10);
        recipientShares[2] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc3), 30_00000, 20);

        // Set up our {TreasuryManagerFactory} and approve our implementation
        _deployWithRecipients(recipientShares, 20_00000, 10_00000);

        // Confirm the shares are set
        assertEq(feeSplitManager.creatorShare(), 20_00000);
        assertEq(feeSplitManager.ownerShare(), 10_00000);

        // Mint some NFTs to our user
        erc1.mint(address(this), 0);
        erc1.mint(address(this), 1);
        erc2.mint(address(this), 0);
        erc3.mint(address(this), 0);

        // Allocate ETH to the manager
        _allocateFees(10 ether);

        // Build a claim of all our tokens
        address[] memory claimErc721 = new address[](3);
        claimErc721[0] = address(erc1);
        claimErc721[1] = address(erc2);
        claimErc721[2] = address(erc3);

        uint[][] memory claimTokenIds = new uint[][](3);
        claimTokenIds[0] = new uint[](2);
        claimTokenIds[0][0] = 0;
        claimTokenIds[0][1] = 1;
        claimTokenIds[1] = new uint[](1);
        claimTokenIds[1][0] = 0;
        claimTokenIds[2] = new uint[](1);
        claimTokenIds[2][0] = 0;

        // Confirm the shares are set
        assertEq(feeSplitManager.creatorFees(), 2 ether);
        assertEq(feeSplitManager.ownerFees(), 1 ether);
        assertEq(feeSplitManager.managerFees(), 7 ether);

        // Reset our ETH balance to ensure that it doesn't conflict with tests
        deal(address(this), 0);

        feeSplitManager.claim(
            abi.encode(
                ERC721OwnerFeeSplitManager.ClaimParams(claimErc721, claimTokenIds)
            )
        );

        // Our manager should hold 10 ether, minus the creator fees, owner fees and tokens
        // that we have claimed against.
        assertEq(payable(address(feeSplitManager)).balance, 8.265 ether);

        // As the creator AND owner, we have taken a percentage
        assertEq(payable(address(this)).balance, 1.735 ether);

        // Confirm the total fees available for each side
        assertEq(feeSplitManager.creatorFees(), 2 ether, 'Invalid creatorFees');
        assertEq(feeSplitManager.ownerFees(), 1 ether, 'Invalid ownerFees');
        assertEq(feeSplitManager.managerFees(), 7 ether, 'Invalid managerFees');

        assertEq(feeSplitManager.amountClaimed(address(erc1), 0), 0.14 ether);
        assertEq(feeSplitManager.amountClaimed(address(erc1), 1), 0.14 ether);
        assertEq(feeSplitManager.amountClaimed(address(erc1), 2), 0);
        assertEq(feeSplitManager.amountClaimed(address(erc2), 0), 0.35 ether);
        assertEq(feeSplitManager.amountClaimed(address(erc2), 1), 0);
        assertEq(feeSplitManager.amountClaimed(address(erc3), 0), 0.105 ether);
        assertEq(feeSplitManager.amountClaimed(address(erc3), 1), 0);

        // Mint a new NFT and make a claim against an existing and a new
        erc2.mint(address(this), 1);

        // Build a claim of a subset of tokens
        claimErc721 = new address[](1);
        claimErc721[0] = address(erc2);

        claimTokenIds = new uint[][](1);
        claimTokenIds[0] = new uint[](2);
        claimTokenIds[0][0] = 0; // Already claimed
        claimTokenIds[0][1] = 1; // Not yet claimed

        feeSplitManager.claim(
            abi.encode(
                ERC721OwnerFeeSplitManager.ClaimParams(claimErc721, claimTokenIds)
            )
        );

        assertEq(payable(address(feeSplitManager)).balance, 7.915 ether);
        assertEq(payable(address(this)).balance, 2.085 ether);

        assertEq(feeSplitManager.creatorFees(), 2 ether, 'Invalid creatorFees');
        assertEq(feeSplitManager.ownerFees(), 1 ether, 'Invalid ownerFees');
        assertEq(feeSplitManager.managerFees(), 7 ether, 'Invalid managerFees');

        assertEq(feeSplitManager.amountClaimed(address(erc1), 0), 0.14 ether);
        assertEq(feeSplitManager.amountClaimed(address(erc1), 1), 0.14 ether);
        assertEq(feeSplitManager.amountClaimed(address(erc1), 2), 0);
        assertEq(feeSplitManager.amountClaimed(address(erc2), 0), 0.35 ether);
        assertEq(feeSplitManager.amountClaimed(address(erc2), 1), 0.35 ether);
        assertEq(feeSplitManager.amountClaimed(address(erc3), 0), 0.105 ether);
        assertEq(feeSplitManager.amountClaimed(address(erc3), 1), 0);

        // Capture the amount of ETH that this account holds, before dealing new balance
        uint balanceBefore = payable(address(this)).balance;

        // Allocate and deal more fees
        _allocateFees(8 ether);
        deal(address(this), 2 ether);
        (bool _sent,) = payable(address(feeSplitManager)).call{value: 2 ether}('');
        assertTrue(_sent, 'Unable to send FeeSplitManager ETH');

        // Reset our balance to the original balance
        deal(address(this), balanceBefore);

        feeSplitManager.claim(
            abi.encode(
                ERC721OwnerFeeSplitManager.ClaimParams(claimErc721, claimTokenIds)
            )
        );

        assertEq(payable(address(feeSplitManager)).balance, 16.175 ether);
        assertEq(payable(address(this)).balance, 3.825 ether);

        assertEq(feeSplitManager.creatorFees(), 3.6 ether, 'Invalid creatorFees');
        assertEq(feeSplitManager.ownerFees(), 2 ether, 'Invalid ownerFees');
        assertEq(feeSplitManager.managerFees(), 14.4 ether, 'Invalid managerFees');

        assertEq(feeSplitManager.amountClaimed(address(erc1), 0), 0.14 ether);
        assertEq(feeSplitManager.amountClaimed(address(erc1), 1), 0.14 ether);
        assertEq(feeSplitManager.amountClaimed(address(erc1), 2), 0);
        assertEq(feeSplitManager.amountClaimed(address(erc2), 0), 0.72 ether);
        assertEq(feeSplitManager.amountClaimed(address(erc2), 1), 0.72 ether);
        assertEq(feeSplitManager.amountClaimed(address(erc3), 0), 0.105 ether);
        assertEq(feeSplitManager.amountClaimed(address(erc3), 1), 0);
    }

    function test_CannotClaimMultipleTimesAgainstTheSameToken() public {
        ERC721OwnerFeeSplitManager.ERC721Share[] memory recipientShares = new ERC721OwnerFeeSplitManager.ERC721Share[](1);
        recipientShares[0] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc1), 100_00000, 10);

        // Set up our {TreasuryManagerFactory} and approve our implementation
        _deployWithRecipients(recipientShares, 20_00000, 10_00000);

        // Mint some NFTs
        erc1.mint(address(this), 1);
        erc1.mint(address(this), 2);

        // Build a claim of all our tokens
        address[] memory claimErc721 = new address[](1);
        claimErc721[0] = address(erc1);

        uint[][] memory claimTokenIds = new uint[][](1);
        claimTokenIds[0] = new uint[](2);
        claimTokenIds[0][0] = 1;
        claimTokenIds[0][1] = 1;

        // Allocate 10 ETH to the manager
        _allocateFees(10 ether);

        // Before our claim, remove any ETH held by this test address
        deal(address(this), 0);

        // We can execute a claim that, even though requesting 10% twice from tokenId 1, it will only claim
        // 10% once as we negate the duplicate tokenId claim.
        feeSplitManager.claim(
            abi.encode(
                ERC721OwnerFeeSplitManager.ClaimParams(claimErc721, claimTokenIds)
            )
        );

        // Our claim should have claimed 10% of the ETH, as we only have 10% of the shares. The actual
        // claimed amount is 0.7 eth as 10% goes to owner and 20% to creators. The creator fees are held
        // in the manager to be claimed, but as the owner of the manager we will have claimed our 1 ether
        // of fees in this same transaction.
        // Therefore, 0.7 in ERC721 holder fees and 1 ether in owner fees.
        assertEq(payable(address(feeSplitManager)).balance, 8.3 ether);
        assertEq(payable(address(this)).balance, 1.7 ether);

        // We can not attempt to make another claim with tokenId 2, but this time splitting it across two
        // entries of the same ERC721, rather than a duplicate within a single ERC721 claim param.
        claimErc721 = new address[](2);
        claimErc721[0] = address(erc1);
        claimErc721[1] = address(erc1);

        claimTokenIds = new uint[][](2);
        claimTokenIds[0] = new uint[](1);
        claimTokenIds[0][0] = 2;
        claimTokenIds[1] = new uint[](1);
        claimTokenIds[1][0] = 2;

        feeSplitManager.claim(
            abi.encode(
                ERC721OwnerFeeSplitManager.ClaimParams(claimErc721, claimTokenIds)
            )
        );

        // Our claim should have claimed a total of 20% of the ETH, as we only have 10% of the shares from
        // the first claim, and 10% from the second claim. The actual claimed amount is 0.7 eth as 10% goes
        // to owner and 20% to creators. The owner and creator fees are held in the manager to be claimed.
        // Therefore, 0.7 in ERC721 holder fees, plus the existing 1.7 ether already claimed.
        assertEq(payable(address(feeSplitManager)).balance, 7.6 ether);
        assertEq(payable(address(this)).balance, 2.4 ether);
    }

    function test_ValidateClaimParamsHandlesInvalidCases(address _invalidCaller) public {
        // Ensure that the caller is not the zero address
        vm.assume(_invalidCaller != address(0));

        // Ensure that the caller is not the owner of the implementation (as they are always approved)
        vm.assume(_invalidCaller != address(this));

        // Setup the manager with valid share configuration
        ERC721OwnerFeeSplitManager.ERC721Share[] memory recipientShares = new ERC721OwnerFeeSplitManager.ERC721Share[](3);
        recipientShares[0] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc1), 20_00000, 10);
        recipientShares[1] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc2), 50_00000, 10);
        recipientShares[2] = ERC721OwnerFeeSplitManager.ERC721Share(address(erc3), 30_00000, 20);
        _deployWithRecipients(recipientShares, 20_00000, 0);

        // Mint some NFTs
        erc1.mint(_invalidCaller, 1);
        erc1.mint(_invalidCaller, 2);
        erc2.mint(_invalidCaller, 1);

        // Test case 1: Different array lengths of erc721 and tokenIds fails
        address[] memory erc721s = new address[](2);
        erc721s[0] = address(erc1);
        erc721s[1] = address(erc2);

        uint[][] memory tokenIds = new uint[][](1);
        tokenIds[0] = new uint[](1);
        tokenIds[0][0] = 1;

        bytes memory params = abi.encode(
            ERC721OwnerFeeSplitManager.ClaimParams(erc721s, tokenIds)
        );

        vm.expectRevert(ERC721OwnerFeeSplitManager.InvalidClaimParams.selector);
        feeSplitManager.isValidRecipient(_invalidCaller, params);

        // Test case 2: Duplicate tokenId in the same erc721 in the ClaimParams will pass, but won't be claimed against
        // multiple times.
        erc721s = new address[](1);
        erc721s[0] = address(erc1);

        tokenIds = new uint[][](1);
        tokenIds[0] = new uint[](2);
        tokenIds[0][0] = 1;
        tokenIds[0][1] = 1; // Duplicate tokenId

        params = abi.encode(
            ERC721OwnerFeeSplitManager.ClaimParams(erc721s, tokenIds)
        );

        feeSplitManager.isValidRecipient(_invalidCaller, params);

        // Test case 3: Duplicate erc721 with the same tokenId in the ClaimParams will pass, but won't be claimed against
        // multiple times.
        erc721s = new address[](2);
        erc721s[0] = address(erc1);
        erc721s[1] = address(erc1); // Duplicate ERC721 address

        tokenIds = new uint[][](2);
        tokenIds[0] = new uint[](1);
        tokenIds[0][0] = 1;
        tokenIds[1] = new uint[](1);
        tokenIds[1][0] = 1; // Same tokenId as before

        params = abi.encode(
            ERC721OwnerFeeSplitManager.ClaimParams(erc721s, tokenIds)
        );

        feeSplitManager.isValidRecipient(_invalidCaller, params);

        // Test case 4: Duplicate erc721 with different tokenId in ClaimParams passes
        erc721s = new address[](2);
        erc721s[0] = address(erc1);
        erc721s[1] = address(erc1); // Duplicate ERC721 address

        tokenIds = new uint[][](2);
        tokenIds[0] = new uint[](1);
        tokenIds[0][0] = 1;
        tokenIds[1] = new uint[](1);
        tokenIds[1][0] = 2; // Different tokenId

        params = abi.encode(
            ERC721OwnerFeeSplitManager.ClaimParams(erc721s, tokenIds)
        );

        // This should pass validation but fail because we don't own the NFTs
        assertFalse(feeSplitManager.isValidRecipient(address(0x123), params));

        // Let's verify more thoroughly that it passed validation by checking with a real owner
        bool result = feeSplitManager.isValidRecipient(_invalidCaller, params);
        
        // Should be true since the validation passed and we're the owner of both tokens
        assertTrue(result);

        // Test case 5: Empty erc721 array should fail
        erc721s = new address[](0);
        tokenIds = new uint[][](0);

        params = abi.encode(
            ERC721OwnerFeeSplitManager.ClaimParams(erc721s, tokenIds)
        );

        vm.expectRevert(ERC721OwnerFeeSplitManager.InvalidClaimParams.selector);
        feeSplitManager.isValidRecipient(_invalidCaller, params);
    }

    function _createERC721(address _recipient) internal returns (uint tokenId_) {
        // Flaunch another memecoin to mint a tokenId
        address memecoin = positionManager.flaunch(
            PositionManager.FlaunchParams({
                name: 'Token Name',
                symbol: 'TOKEN',
                tokenUri: 'https://flaunch.gg/',
                initialTokenFairLaunch: supplyShare(50),
                fairLaunchDuration: 30 minutes,
                premineAmount: 0,
                creator: _recipient,
                creatorFeeAllocation: 0,
                flaunchAt: 0,
                initialPriceParams: abi.encode(''),
                feeCalculatorParams: abi.encode(1_000)
            })
        );

        // Get the tokenId from the memecoin address
        return flaunch.tokenId(memecoin);
    }

    function _deployWithRecipients(ERC721OwnerFeeSplitManager.ERC721Share[] memory _recipientShares, uint _creatorShare, uint _ownerShare) internal {
        // Initialize our token
        address payable manager = treasuryManagerFactory.deployAndInitializeManager({
            _managerImplementation: managerImplementation,
            _owner: address(this),
            _data: abi.encode(
                ERC721OwnerFeeSplitManager.InitializeParams(_creatorShare, _ownerShare, _recipientShares)
            )
        });

        feeSplitManager = ERC721OwnerFeeSplitManager(manager);
    }

    function _allocateFees(uint _amount) internal {
        // Mint ETH to the flETH contract to facilitate unwrapping
        deal(address(this), _amount);
        WETH.deposit{value: _amount}();
        WETH.transfer(address(positionManager), _amount);

        positionManager.allocateFeesMock({
            _poolId: PoolId.wrap(bytes32('1')),  // Can be mocked to anything
            _recipient: payable(address(feeSplitManager)),
            _amount: _amount
        });
    }

    function _allocatePoolFees(uint _amount, uint _tokenId) internal {
        // Mint ETH to the flETH contract to facilitate unwrapping
        deal(address(this), _amount);
        WETH.deposit{value: _amount}();
        WETH.approve(address(feeEscrow), _amount);

        // Discover the PoolId from the tokenId
        PoolId poolId = feeSplitManager.tokenPoolId(
            feeSplitManager.flaunchTokenInternalIds(address(flaunch), _tokenId)
        );

        // Allocate our fees directly to the FeeEscrow
        feeEscrow.allocateFees({
            _poolId: poolId,
            _recipient: payable(address(feeSplitManager)),
            _amount: _amount
        });
    }

}
