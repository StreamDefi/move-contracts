#[test_only]
module stream::withdraw_tests {
    use std::signer;
    use aptos_framework::coin;
    use stream::vault::VaultToken;
    use stream::test_helpers;
    use stream::vault;

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    #[expected_failure(abort_code = stream::vault::EZERO_AMOUNT)]
    fun test_RevertsIfAmountIsNotGreaterThanZero(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);
        test_helpers::mint(user, 1000);
        vault::deposit(user, test_helpers::one_apt());
        vault::withdrawInstantly(user, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    #[expected_failure(abort_code = stream::vault::EINVALID_AMOUNT)]
    fun test_RevertsIfInstantWithdrawExceedsDepositAmount(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);
        test_helpers::mint(user, 1000);
        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);
        vault::withdrawInstantly(user, deposit_amount + 1);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    #[expected_failure(abort_code = stream::vault::EINVALID_ROUND)]
    fun test_RevertsIfAttemptingInstantWithdrawInPrevRound(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);
        test_helpers::mint(user, 1000);
        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);

        vault::rollToNextRound(keeper, deposit_amount);

        vault::withdrawInstantly(user, deposit_amount);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    fun test_fullInstantWithdrawUpdatesDepositReceipt(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);

        test_helpers::mint(user, 1000);
        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);
        test_helpers::assert_deposit_receipt(user, 1, deposit_amount, 0);

        vault::withdrawInstantly(user, deposit_amount);
        test_helpers::assert_deposit_receipt(user, 1, 0, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    fun test_partialInstantWIthdrawUpdatesDepositReceipt(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);

        test_helpers::mint(user, 1000);
        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);
        test_helpers::assert_deposit_receipt(user, 1, deposit_amount, 0);

        vault::withdrawInstantly(user, deposit_amount / 2);
        test_helpers::assert_deposit_receipt(user, 1, deposit_amount / 2, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    fun test_fullInstantWithdrawUpdatesTotalPending(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);

        test_helpers::mint(user, 1000);
        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);
        assert!(vault::totalPending() == deposit_amount, 0);

        vault::withdrawInstantly(user, deposit_amount);
        assert!(vault::totalPending() == 0, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    fun test_partialInstantWithdrawUpdatesTotalPending(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);

        test_helpers::mint(user, 1000);
        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);
        assert!(vault::totalPending() == deposit_amount, 0);

        vault::withdrawInstantly(user, deposit_amount / 2);
        assert!(vault::totalPending() == deposit_amount / 2, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    fun test_fullInstantWithdrawUpdatesBalancesProperly(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);

        test_helpers::mint(user, 1000);
        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);
        assert!(vault::remainingBalance() == deposit_amount, 0);

        vault::withdrawInstantly(user, deposit_amount);
        assert!(vault::remainingBalance() == 0, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    fun test_partialInstantWithdrawUpdatesBalancesProperly(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);

        test_helpers::mint(user, 1000);
        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);
        assert!(vault::remainingBalance() == deposit_amount, 0);

        vault::withdrawInstantly(user, deposit_amount / 2);
        assert!(vault::remainingBalance() == deposit_amount / 2, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    #[expected_failure(abort_code = stream::vault::EZERO_AMOUNT)]
    fun test_RevertIfInitatingZeroShareWithdraw(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);
        test_helpers::mint(user, 1000);

        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);

        vault::rollToNextRound(keeper, deposit_amount);

        vault::initiateWithdraw(user, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    fun test_maxRedeemsIfDepositerHasUnredeemedShares(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);
        test_helpers::mint(user, 1000);

        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);

        vault::rollToNextRound(keeper, deposit_amount);
        assert!(vault::total_unredeemed_shares() == deposit_amount, 0);

        let withdraw_amount = deposit_amount / 2;
        vault::initiateWithdraw(user, withdraw_amount);

        // vault max redeems and transfers back to value the amount withdrawn
        assert!(coin::balance<VaultToken>(signer::address_of(user)) == deposit_amount - withdraw_amount, 0);
        assert!(vault::total_withdraw_shares() == withdraw_amount, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    #[expected_failure(abort_code = stream::vault::EEXCEEDS_AVAILABLE)]
    fun test_RevertIfDepositerHasNoUnreedeemedShares(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);
        test_helpers::mint(user, 1000);

        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);
        vault::initiateWithdraw(user, deposit_amount);
    }
}
