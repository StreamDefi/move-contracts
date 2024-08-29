#[test_only]
module stream::setters_tests {
    use std::signer;
    use aptos_framework::account;
    use stream::test_helpers;
    use stream::vault;

    #[test(owner = @0xcafe, keeper = @0x123)]
    #[expected_failure(abort_code = stream::vault::EZERO_ADDRESS)]
    fun test_RevertWhenSettingKeeperToZeroAddress(owner: &signer, keeper: &signer) {
        test_helpers::setup(owner, keeper);
        vault::setNewKeeper(owner, @0x0);
    }

    #[test(owner = @0xcafe, keeper = @0x123)]
    #[expected_failure(abort_code = stream::vault::EZERO_ADDRESS)]
    fun test_RevertWhenNonOwnerChangesKeeper(owner: &signer, keeper: &signer) {
        test_helpers::setup(owner, keeper);
        let non_owner = &account::create_signer_for_test(@0x456);
        vault::setNewKeeper(non_owner, @0x0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, new_keeper = @0x234)]
    fun test_settingNewKeeper(owner: &signer, keeper: &signer, new_keeper: &signer) {
        test_helpers::setup(owner, keeper);
        let new_keeper_addr = signer::address_of(new_keeper);
        vault::setNewKeeper(owner, new_keeper_addr);
        assert!(vault::keeper() == new_keeper_addr, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123, new_keeper = @0x234)]
    #[expected_failure(abort_code = stream::vault::EUNAUTHORIZED)]
    fun test_RevertIfOldKeeperMakesCallAfterChanged(owner: &signer, keeper: &signer, new_keeper: &signer) {
        test_helpers::setup(owner, keeper);
        let new_keeper_addr = signer::address_of(new_keeper);
        vault::setNewKeeper(owner, new_keeper_addr);
        assert!(vault::keeper() == new_keeper_addr, 0);
        vault::rollToNextRound(keeper, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123)]
    #[expected_failure(abort_code = stream::vault::EZERO_AMOUNT)]
    fun test_RevertIfCapIsSetToZero(owner: &signer, keeper: &signer) {
        test_helpers::setup(owner, keeper);
        vault::setCap(owner, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123)]
    fun test_newCapGetsSet(owner: &signer, keeper: &signer) {
        test_helpers::setup(owner, keeper);
        assert!(vault::cap() > 10, 0);
        vault::setCap(owner, 10);
        assert!(vault::cap() == 10, 0);
    }

    #[test(owner = @0xcafe, keeper = @0x123)]
    #[expected_failure(abort_code = stream::vault::EUNAUTHORIZED)]
    fun test_NonOwnerCannotCallSetCap(owner: &signer, keeper: &signer) {
        test_helpers::setup(owner, keeper);
        let non_owner = &account::create_signer_for_test(@0x456);
        vault::setCap(non_owner, 10);
    }

    #[test(owner = @0xcafe, keeper = @0x123, user = @0x234)]
    #[expected_failure(abort_code = stream::vault::EEXCEEDS_CAP)]
    fun test_canSetCapBelowCurrentDeposits(owner: &signer, keeper: &signer, user: &signer) {
        test_helpers::setup(owner, keeper);

        // 1e9 tokens is the cap.
        let cap = 1000000000;
        test_helpers::mint(user, cap);
        let deposit_amount = cap * test_helpers::one_apt();
        vault::deposit(user, deposit_amount - test_helpers::one_apt());

        vault::setCap(owner, cap - 1);
        vault::deposit(user, test_helpers::one_apt());
    }
}
