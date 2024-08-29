#[test_only]
module stream::withdraw_tests {
    use std::signer;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::AptosCoin;
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

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    fun test_withdrawReceiptCreatedForNewWithdraw(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);
        test_helpers::mint(user, 1000);

        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);

        vault::rollToNextRound(keeper, deposit_amount);

        test_helpers::assert_withdrawal(user, 0, 0);

        let withdraw_amount = deposit_amount / 2;
        vault::initiateWithdraw(user, withdraw_amount);

        test_helpers::assert_withdrawal(user, 2, withdraw_amount);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    fun test_doubleWithdrawAddsToWithdrawalReceipt(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);
        test_helpers::mint(user, 1000);

        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);

        vault::rollToNextRound(keeper, deposit_amount);

        test_helpers::assert_withdrawal(user, 0, 0);

        let withdraw_amount_1 = deposit_amount / 3;
        vault::initiateWithdraw(user, withdraw_amount_1);
        test_helpers::assert_withdrawal(user, 2, withdraw_amount_1);

        let withdraw_amount_2 = deposit_amount / 2;
        vault::initiateWithdraw(user, withdraw_amount_2);
        test_helpers::assert_withdrawal(user, 2, withdraw_amount_1 + withdraw_amount_2);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    #[expected_failure(abort_code = stream::vault::EEXCEEDS_AVAILABLE)]
    fun test_RevertIfUserHasInsufficientShares(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);
        test_helpers::mint(user, 1000);

        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);

        vault::rollToNextRound(keeper, deposit_amount);

        vault::initiateWithdraw(user, deposit_amount + 1);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    #[expected_failure(abort_code = stream::vault::EEXISTING_WITHDRAWAL)]
    fun test_RevertIfDoubleInitiatingWithdrawInSepRounds(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);
        test_helpers::mint(user, 1000);

        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);

        vault::rollToNextRound(keeper, deposit_amount);
        vault::initiateWithdraw(user, deposit_amount / 2);

        vault::add_to_balance(keeper, deposit_amount);
        vault::rollToNextRound(keeper, deposit_amount);
        vault::initiateWithdraw(user, deposit_amount / 2);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    fun test_currentQueuedWithdrawSharesIsMaintained(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);
        test_helpers::mint(user, 1000);

        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);

        vault::rollToNextRound(keeper, deposit_amount);

        assert!(vault::currentQueuedWithdrawShares() == 0, 0);
        let withdraw_amount = deposit_amount / 2;
        vault::initiateWithdraw(user, withdraw_amount);
        assert!(vault::currentQueuedWithdrawShares() == withdraw_amount, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    #[expected_failure(abort_code = stream::vault::EWITHDRAWAL_NOT_INITIATED)]
    fun test_RevertIfNoWithdrawInitiated(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);
        test_helpers::mint(user, 1000);

        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);

        vault::rollToNextRound(keeper, deposit_amount);
        vault::completeWithdraw(user);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    #[expected_failure(abort_code = stream::vault::EINVALID_ROUND)]
    fun test_RevertIfCompletingWithdrawPreMaturely(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);
        test_helpers::mint(user, 1000);

        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);

        vault::rollToNextRound(keeper, deposit_amount);
        vault::initiateWithdraw(user, deposit_amount);
        vault::completeWithdraw(user);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    fun test_updatesWithdrawReceiptAfterCompleting(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);
        test_helpers::mint(user, 1000);

        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);

        vault::rollToNextRound(keeper, deposit_amount);
        test_helpers::assert_withdrawal(user, 0, 0);

        let withdraw_amount = deposit_amount / 2;
        vault::initiateWithdraw(user, withdraw_amount);
        test_helpers::assert_withdrawal(user, 2, withdraw_amount);

        vault::add_to_balance(keeper, deposit_amount);
        vault::rollToNextRound(keeper, deposit_amount);

        vault::completeWithdraw(user);
        test_helpers::assert_withdrawal(user, 2, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    fun test_withdrawerReceivesFundsFromVault(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);
        test_helpers::mint(user, 1000);

        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);
        assert!(vault::remainingBalance() == deposit_amount, 0);

        vault::rollToNextRound(keeper, deposit_amount);
        let keeper_addr = signer::address_of(keeper);
        assert!(coin::balance<AptosCoin>(keeper_addr) == deposit_amount, 0);
        assert!(vault::remainingBalance() == 0, 0);

        let withdraw_amount = deposit_amount / 2;
        vault::initiateWithdraw(user, withdraw_amount);
        assert!(coin::balance<AptosCoin>(keeper_addr) == deposit_amount, 0);
        assert!(vault::remainingBalance() == 0, 0);

        vault::add_to_balance(keeper, deposit_amount);
        vault::rollToNextRound(keeper, deposit_amount);
        assert!(vault::remainingBalance() == withdraw_amount, 0);
        assert!(coin::balance<AptosCoin>(keeper_addr) == deposit_amount - withdraw_amount, 0);

        let pre_balance = coin::balance<AptosCoin>(signer::address_of(user));
        vault::completeWithdraw(user);
        let post_balance = coin::balance<AptosCoin>(signer::address_of(user));
        assert!(coin::balance<AptosCoin>(keeper_addr) == deposit_amount - withdraw_amount, 0);
        assert!(vault::remainingBalance() == 0, 0);
        assert!(post_balance == pre_balance + withdraw_amount, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    fun test_queuedWithdrawSharesIsProperlyMaintained(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);
        test_helpers::mint(user, 1000);

        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);

        vault::rollToNextRound(keeper, deposit_amount);

        let withdraw_amount = deposit_amount / 2;
        vault::initiateWithdraw(user, withdraw_amount);

        vault::add_to_balance(keeper, deposit_amount);
        vault::rollToNextRound(keeper, deposit_amount);
        assert!(vault::queuedWithdrawShares() == withdraw_amount, 0);

        vault::completeWithdraw(user);
        assert!(vault::queuedWithdrawShares() == 0, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    fun test_sharesGetBurnedOnComplete(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);
        test_helpers::mint(user, 1000);

        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);

        vault::rollToNextRound(keeper, deposit_amount);

        let withdraw_amount = deposit_amount / 2;
        vault::initiateWithdraw(user, withdraw_amount);

        vault::add_to_balance(keeper, deposit_amount);
        vault::rollToNextRound(keeper, deposit_amount);
        assert!(vault::totalSupply() == (deposit_amount as u128), 0);

        vault::completeWithdraw(user);
        assert!(vault::totalSupply() == ((deposit_amount - withdraw_amount) as u128), 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    fun test_lastQueuedWithdrawAmountIsProperlyMaintained(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);
        test_helpers::mint(user, 1000);

        let deposit_amount = test_helpers::one_apt();
        vault::deposit(user, deposit_amount);

        vault::rollToNextRound(keeper, deposit_amount);

        let withdraw_amount = deposit_amount / 2;
        vault::initiateWithdraw(user, withdraw_amount);

        vault::add_to_balance(keeper, deposit_amount);
        vault::rollToNextRound(keeper, deposit_amount);
        assert!(vault::lastQueuedWithdrawAmount() == withdraw_amount, 0);

        vault::completeWithdraw(user);
        assert!(vault::lastQueuedWithdrawAmount() == 0, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123)]
    fun test_multiInitiateWithdraw(owner: &signer, keeper: &signer) {
        test_helpers::setup(owner, keeper);

        let users = vector[@0x1, @0x2, @0x3, @0x4, @0x5, @0x6, @0x7, @0x8, @0x9, @0xa];
        let deposit_amount = test_helpers::one_apt();
        vector::for_each(users, |user_addr| {
            let user = &account::create_signer_for_test(user_addr);
            test_helpers::mint(user, 1000);
            vault::deposit(user, deposit_amount);
            test_helpers::assert_deposit_receipt(user, 1, deposit_amount, 0);
        });
        test_helpers::assert_vault_state(1, 0, 0, deposit_amount * 10, 0, 0, 0, 0, 0);

        vault::rollToNextRound(keeper, deposit_amount * 10);
        test_helpers::assert_vault_state(2, deposit_amount * 10, 0, 0, 0, 0, 0, (deposit_amount as u128) * 10, deposit_amount);

        vector::for_each(users, |user_addr| {
            let user = &account::create_signer_for_test(user_addr);
            vault::initiateWithdraw(user, deposit_amount);
            test_helpers::assert_withdrawal(user, 2, deposit_amount);
        });

        assert!(vault::total_withdraw_shares() == deposit_amount * 10, vault::total_withdraw_shares());
    }

    #[test(owner = @0xcafe, keeper = @0x123)]
    fun test_multiCompleteWithdraw(owner: &signer, keeper: &signer) {
        test_helpers::setup(owner, keeper);

        let users = vector[@0x1, @0x2, @0x3, @0x4, @0x5, @0x6, @0x7, @0x8, @0x9, @0xa];
        let deposit_amount = test_helpers::one_apt();
        vector::for_each(users, |user_addr| {
            let user = &account::create_signer_for_test(user_addr);
            test_helpers::mint(user, 1000);
            vault::deposit(user, deposit_amount);
            test_helpers::assert_deposit_receipt(user, 1, deposit_amount, 0);
        });
        test_helpers::assert_vault_state(1, 0, 0, deposit_amount * 10, 0, 0, 0, 0, 0);

        vault::rollToNextRound(keeper, deposit_amount * 10);
        test_helpers::assert_vault_state(2, deposit_amount * 10, 0, 0, 0, 0, 0, (deposit_amount as u128) * 10, deposit_amount);

        vector::for_each(users, |user_addr| {
            let user = &account::create_signer_for_test(user_addr);
            vault::initiateWithdraw(user, deposit_amount);
            test_helpers::assert_withdrawal(user, 2, deposit_amount);
        });

        vault::add_to_balance(keeper, deposit_amount * 10);
        vault::rollToNextRound(keeper, deposit_amount * 10);
        test_helpers::assert_vault_state(3, 0, deposit_amount * 10, 0, deposit_amount * 10, deposit_amount * 10, 0, ((deposit_amount * 10) as u128), deposit_amount);

        vector::for_each(users, |user_addr| {
            test_helpers::assert_withdrawal(&account::create_signer_for_test(user_addr), 2, deposit_amount);
        });

        // complete the withdraw
        vector::for_each(users, |user_addr| {
            let user = &account::create_signer_for_test(user_addr);
            vault::completeWithdraw(user);
            test_helpers::assert_withdrawal(user, 2, 0);
        });

        test_helpers::assert_vault_state(3, 0, deposit_amount * 10, 0, 0, 0, 0, 0, deposit_amount);
        assert!(vault::remainingBalance() == 0, 0);
    }
}
