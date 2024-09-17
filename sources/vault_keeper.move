module stream::vault_keeper {
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_std::type_info;
    use std::signer;
    use stream::vault;
    use stream_managers::managers;

    /// VaultKeeper: Not enough assets
    const EINSUFFICIENT_ASSETS: u64 = 1;
    /// VaultKeeper: Unauthorized
    const EUNAUTHORIZED: u64 = 2;

    public entry fun rollRound(manager: &signer, locked_balance: u64) {
        assert!(signer::address_of(manager) == managers::manager(type_info::type_name<AptosCoin>()), EUNAUTHORIZED);

        let curr_balance = vault::remainingBalance() + locked_balance;
        let queued_withdraw_amount = vault::getCurrQueuedWithdrawAmount(curr_balance);
        let last_queued_withdraw_amount = vault::lastQueuedWithdrawAmount();
        vault::add_to_balance(manager, queued_withdraw_amount - last_queued_withdraw_amount);
        assert!(vault::remainingBalance() >= queued_withdraw_amount, EINSUFFICIENT_ASSETS);

        // This sends the asset directly to the manager so we don't need to do another transfer.
        vault::rollToNextRound(manager, locked_balance);
    }
}
