module stream::vault {
    use aptos_framework::aptos_account;
    use aptos_framework::coin::{Coin, MintCapability, BurnCapability};
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_std::smart_table::{Self, SmartTable};
    use std::option;
    use std::signer;
    use std::string;
    use aptos_framework::aptos_coin::AptosCoin;
    use stream::shares_math;

    friend stream::vault_keeper;

    // To be updated before deploying a new vault
    const TOKEN_DECIMALS: u8 = 8;
    const TOKEN_NAME: vector<u8> = b"Stream Vault token [ETH]";
    const TOKEN_SYMBOL: vector<u8> = b"svETH";
    const MINIMUM_SUPPLY: u64 = 100000000; // 1e8
    const TOKEN_CAP: u64 = 100000000000000000; // 1e17

    /// Account is not authorized to perform the action
    const EUNAUTHORIZED: u64 = 1;
    /// Vault is not public
    const EVAULT_IS_NOT_PUBLIC: u64 = 2;
    /// Amount cannot be zero
    const EZERO_AMOUNT: u64 = 3;
    /// Amount exceeds the cap
    const EEXCEEDS_CAP: u64 = 4;
    /// Amount is less than the minimum supply
    const EINSUFFICIENT_BALANCE: u64 = 5;
    /// Creditor is invalid
    const EINVALID_CREDITOR: u64 = 6;
    /// Invalid round
    const EINVALID_ROUND: u64 = 7;
    /// Invalid amount
    const EINVALID_AMOUNT: u64 = 8;
    /// Existing withdrawal
    const EEXISTING_WITHDRAWAL: u64 = 9;
    /// Withdrawal not initiated
    const EWITHDRAWAL_NOT_INITIATED: u64 = 10;
    /// Exceeds available shares
    const EEXCEEDS_AVAILABLE: u64 = 11;
    /// Zero address
    const EZERO_ADDRESS: u64 = 12;

    // 0x1::aptos_coin::AptosCoin
    // 0x123::stream::VaultToken
    struct VaultToken {}

    // This data is stored directly on the contract account, mimicking global state in Solidity/EVM.
    struct Vault has key {
        // Minimum supply of the vault shares issued, for ETH it's 10**10
        minimum_supply: u64,
        // Vault cap
        cap: u64,
    }

    // This data is stored directly on the contract account, mimicking global state in Solidity/EVM.
    struct VaultBalance has key {
        // TODO: Update coin type to the right type before deploying
        balance: Coin<AptosCoin>,
        unredeemed_shares: Coin<VaultToken>,
        withdrawal_shares: Coin<VaultToken>,
        deposits: SmartTable<address, DepositReceipt>,
        withdrawals: SmartTable<address, Withdrawal>,
        mint_cap: MintCapability<VaultToken>,
        burn_cap: BurnCapability<VaultToken>,
    }

    // This data is stored directly on the contract account, mimicking global state in Solidity/EVM.
    struct VaultState has key {
        //  Current round number. `round` represents the number of `period`s elapsed.
        round: u64,
        // Amount that is currently locked for executing strategy
        locked_amount: u64,
        // Amount that was locked for executing strategy in the previous round
        // used for calculating performance fee deduction
        last_locked_amount: u64,
        // Stores the total tally of how much of `asset` there is
        // to be used to mint rSTREAM tokens
        total_pending: u64,
        // Total amount of queued withdrawal shares from previous rounds (doesn't include the current round)
        queued_withdraw_shares: u64,
        /// On every round's close, the pricePerShare value of an rTHETA token is stored
        /// This is used to determine the number of shares to be returned
        /// to a user with their DepositReceipt.depositAmount
        round_price_per_share: SmartTable<u64, u64>,
        /// The amount of 'asset' that was queued for withdrawal in the last round
        last_queued_withdraw_amount: u64,
        /// The amount of shares that are queued for withdrawal in the current round
        current_queued_withdraw_shares: u64,
    }

    // This data is stored directly on the contract account, mimicking global state in Solidity/EVM.
    struct VaultManagement has key {
        owner: address,
        keeper: address,
    }

    struct DepositReceipt has copy, drop, store {
        // Maximum of 65535 rounds. Assuming 1 round is 7 days, maximum is 1256 years.
        round: u64,
        // Deposit amount, max 20,282,409,603,651 or 20 trillion ETH deposit
        amount: u64,
        // Unredeemed shares balance
        unredeemed_shares: u64,
    }

    struct Withdrawal has copy, drop, store {
        // Maximum of 65535 rounds. Assuming 1 round is 7 days, maximum is 1256 years.
        round: u64,
        // Number of shares withdrawn
        shares: u64,
    }

    #[event]
    struct Deposit has drop, store {
        account: address,
        amount: u64,
        round: u64,
    }

    #[event]
    struct InitiateWithdraw has drop, store {
        account: address,
        shares: u64,
        round: u64,
    }

    #[event]
    struct Withdraw has drop, store {
        account: address,
        amount: u64,
        shares: u64,
    }

    #[event]
    struct Redeem has drop, store {
        account: address,
        share: u64,
        round: u64,
    }

    #[event]
    struct CapSet has drop, store {
        old_cap: u64,
        new_cap: u64,
    }

    #[event]
    struct InstantWithdraw has drop, store {
        account: address,
        amount: u64,
        round: u64,
    }

    /************************************************
     *  CONSTRUCTOR & INITIALIZATION
     ***********************************************/

    // Only called once when the contract is first deployed.
    // Equivalent to constructor in Solidity.
    fun init_module(vault_signer: &signer) {
        // vault_signer is the signer for @stream
        move_to(vault_signer, VaultManagement {
            owner: @stream,
            keeper: @stream,
        });
        move_to(vault_signer, Vault {
            minimum_supply: MINIMUM_SUPPLY,
            cap: TOKEN_CAP,
        });
        move_to(vault_signer, VaultState {
            // Round starts at 1, same as in the Solidity version
            round: 1,
            locked_amount: 0,
            last_locked_amount: 0,
            total_pending: 0,
            queued_withdraw_shares: 0,
            round_price_per_share: smart_table::new(),
            last_queued_withdraw_amount: 0,
            current_queued_withdraw_shares: 0,
        });

        // Create the vault token.
        // TODO: Make sure name, symbol and decimals are correct before deploying the contract.
        // These cannot be changed after the vault is created.
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<VaultToken>(
            vault_signer,
            string::utf8(TOKEN_NAME),
            string::utf8(TOKEN_SYMBOL),
            TOKEN_DECIMALS,
            true, // Store supply on chain
        );
        coin::destroy_freeze_cap(freeze_cap);
        move_to(vault_signer, VaultBalance {
            balance: coin::zero(),
            unredeemed_shares: coin::zero(),
            withdrawal_shares: coin::zero(),
            deposits: smart_table::new(),
            withdrawals: smart_table::new(),
            mint_cap,
            burn_cap,
        });
    }

    /************************************************
     *  PUBLIC DEPOSITS
     ***********************************************/

    /// Deposits the `asset` from user.
    /// @param amount is the amount of `asset` to deposit
    public entry fun deposit(user: &signer, amount: u64) acquires Vault, VaultBalance, VaultState {
        depositFor(user, amount, signer::address_of(user));
    }

    /// Deposits the `asset` from user added to `creditor`'s deposit.
    /// Used for vault -> vault deposits on the user's behalf
    /// @param amount is the amount of `asset` to deposit
    /// @param creditor is the address that can claim/withdraw deposited amount
    public entry fun depositFor(
        user: &signer,
        amount: u64,
        creditor: address,
    ) acquires Vault, VaultBalance, VaultState {
        assert!(creditor != @0x0, EINVALID_CREDITOR);
        let total_with_deposited_amount = totalBalance() + amount;
        let vault_state = borrow_global_mut<VaultState>(@stream);
        assert!(amount > 0, EZERO_AMOUNT);

        let current_round = vault_state.round;
        let vault_params = borrow_global<Vault>(@stream);
        assert!(total_with_deposited_amount <= vault_params.cap, EEXCEEDS_CAP);
        assert!(
            total_with_deposited_amount >= vault_params.minimum_supply,
            EINSUFFICIENT_BALANCE,
        );

        // Transfer the deposited coins to the vault
        let vault_balance = borrow_global_mut<VaultBalance>(@stream);
        let deposit = coin::withdraw(user, amount);
        coin::merge(&mut vault_balance.balance, deposit);
        event::emit(Deposit {
            account: creditor,
            amount,
            round: current_round,
        });

        let deposit_receipt = smart_table::borrow_mut_with_default(&mut vault_balance.deposits, creditor, DepositReceipt {
            // Default values of 0 to be as similar to Solidity code as possible
            round: 0,
            amount: 0,
            unredeemed_shares: 0,
        });

        let assetPerShare = *smart_table::borrow_with_default(&vault_state.round_price_per_share, deposit_receipt.round, &0);
        let unredeemed_shares = getSharesFromReceipt(
            deposit_receipt,
            current_round,
            assetPerShare,
        );
        let deposit_amount = amount;
        // If we have a pending deposit in the current round, we add on to the pending deposit
        if (current_round == deposit_receipt.round) {
            // No need to check if overflow happens as overflow automatically aborts in Move.
            deposit_amount = deposit_receipt.amount + amount;
        };

        deposit_receipt.round = current_round;
        deposit_receipt.amount = deposit_amount;
        deposit_receipt.unredeemed_shares = unredeemed_shares;
        vault_state.total_pending = vault_state.total_pending + amount;
    }

    /************************************************
     *  WITHDRAWALS
     ***********************************************/

    /// Withdraws the assets on the vault using the outstanding `DepositReceipt.amount`
    /// @param amount is the amount to withdraw
    public entry fun withdrawInstantly(user: &signer, amount: u64) acquires VaultBalance, VaultState {
        assert!(amount > 0, EZERO_AMOUNT);

        let vault_state = borrow_global_mut<VaultState>(@stream);
        let current_round = vault_state.round;
        let user_addr = signer::address_of(user);
        let deposit_receipt = mut_deposit_receipt(user_addr);
        assert!(deposit_receipt.round == current_round, EINVALID_ROUND);

        let receipt_amount = deposit_receipt.amount;
        assert!(receipt_amount >= amount, EINVALID_AMOUNT);

        deposit_receipt.amount = receipt_amount - amount;
        vault_state.total_pending = vault_state.total_pending - amount;

        event::emit(InstantWithdraw {
            account: user_addr,
            amount,
            round: current_round,
        });

        transferAsset(user_addr, amount);
    }

    /// Initiates a withdrawal that can be processed once the round completes
    /// @param numShares is the number of shares to withdraw
    public entry fun initiateWithdraw(user: &signer, num_shares: u64) acquires VaultBalance, VaultState {
        assert!(num_shares > 0, EZERO_AMOUNT);

        let user_addr = signer::address_of(user);
        let deposit_receipt = deposit_receipt(user_addr);
        if (deposit_receipt.amount > 0 || deposit_receipt.unredeemed_shares > 0) {
            maxRedeem(user);
        };
        assert!(shares(user_addr) >= num_shares, EEXCEEDS_AVAILABLE);

        let vault_state = borrow_global_mut<VaultState>(@stream);
        let current_round = vault_state.round;

        let withdrawal = mut_withdrawal(user_addr);
        let withdrawal_is_same_round = withdrawal.round == current_round;

        event::emit(InitiateWithdraw {
            account: user_addr,
            shares: num_shares,
            round: current_round,
        });

        let existing_shares = withdrawal.shares;
        withdrawal.shares = if (withdrawal_is_same_round) {
            existing_shares + num_shares
        } else {
            assert!(existing_shares == 0, EEXISTING_WITHDRAWAL);
            withdrawal.round = current_round;
            num_shares
        };

        let vault_balance = borrow_global_mut<VaultBalance>(@stream);
        coin::merge(&mut vault_balance.withdrawal_shares, coin::withdraw(user, num_shares));
        vault_state.current_queued_withdraw_shares = vault_state.current_queued_withdraw_shares + num_shares;
    }

    /// Completes a scheduled withdrawal from a past round. Uses finalized pps for the round
    public entry fun completeWithdraw(user: &signer) acquires VaultBalance, VaultState {
        let user_addr = signer::address_of(user);
        let withdrawal = mut_withdrawal(user_addr);
        let vault_state = borrow_global_mut<VaultState>(@stream);

        let withdrawal_shares = withdrawal.shares;
        let withdrawal_round = withdrawal.round;

        // This checks if there is a withdrawal
        assert!(withdrawal_shares > 0, EWITHDRAWAL_NOT_INITIATED);
        assert!(withdrawal_round < vault_state.round, EINVALID_ROUND);

        withdrawal.shares = 0;
        vault_state.queued_withdraw_shares = vault_state.queued_withdraw_shares - withdrawal_shares;

        let round_per_share = *smart_table::borrow_with_default(&vault_state.round_price_per_share, withdrawal_round, &0);
        let withdraw_amount = shares_math::sharesToAsset(
            withdrawal_shares,
            round_per_share,
            (TOKEN_DECIMALS as u64),
        );

        event::emit(Withdraw {
            account: user_addr,
            amount: withdraw_amount,
            shares: withdrawal_shares,
        });

        // Burn the withdrawn shares.
        let vault_balance = borrow_global_mut<VaultBalance>(@stream);
        let withdrawn_shares = coin::extract(&mut vault_balance.withdrawal_shares, withdrawal_shares);
        coin::burn(withdrawn_shares, &vault_balance.burn_cap);

        // Transfer underlying tokens to user
        transferAsset(user_addr, withdraw_amount);
        vault_state.last_queued_withdraw_amount = vault_state.last_queued_withdraw_amount - withdraw_amount;
    }

    /************************************************
     *  REDEMPTIONS
     ***********************************************/

    /// Redeems shares that are owed to the account
    /// @param numShares is the number of shares to redeem
    public entry fun redeem(user: &signer, num_shares: u64) acquires VaultBalance, VaultState {
        assert!(num_shares > 0, EZERO_AMOUNT);
        redeem_internal(signer::address_of(user), num_shares, false);
    }

    /// Redeems the entire unredeemedShares balance that is owed to the account
    public entry fun maxRedeem(user: &signer) acquires VaultBalance, VaultState {
        redeem_internal(signer::address_of(user), 0, true);
    }

    fun redeem_internal(user: address, num_shares: u64, is_max: bool) acquires VaultBalance, VaultState {
        let deposit_receipt = mut_deposit_receipt(user);

        // This handles the null case when depositReceipt.round = 0
        // Because we start with round = 1 at `initialize`
        let vault_state = borrow_global<VaultState>(@stream);
        let current_round = vault_state.round;

        let round_price_per_share = *smart_table::borrow_with_default(&vault_state.round_price_per_share, deposit_receipt.round, &0);
        let unredeemed_shares = getSharesFromReceipt(
            deposit_receipt,
            current_round,
            round_price_per_share,
        );
        if (is_max) {
            num_shares = unredeemed_shares;
        };
        assert!(num_shares <= unredeemed_shares, EEXCEEDS_AVAILABLE);

        // If we have a depositReceipt on the same round, BUT we have some unredeemed shares
        // we debit from the unredeemedShares, but leave the amount field intact
        // If the round has past, with no new deposits, we just zero it out for new deposits.
        if (deposit_receipt.round < current_round) {
            deposit_receipt.amount = 0;
        };

        deposit_receipt.unredeemed_shares = unredeemed_shares - num_shares;

        event::emit(Redeem {
            account: user,
            share: num_shares,
            round: current_round,
        });

        // Transfer corresponding vault shares to the user.
        let vault_balance = borrow_global_mut<VaultBalance>(@stream);
        let shares = coin::extract(&mut vault_balance.unredeemed_shares, num_shares);
        aptos_account::deposit_coins(user, shares);
    }

    /************************************************
     *  VAULT OPERATIONS
     ***********************************************/

    public(friend) fun add_to_balance(keeper: &signer, amount: u64) acquires VaultBalance {
        let vault_balance = borrow_global_mut<VaultBalance>(@stream);
        coin::merge(&mut vault_balance.balance, coin::withdraw(keeper, amount));
    }

    /// Rolls to the next round, finalizing prev round pricePerShare and minting new shares
    /// Keeper only deposits enough to fulfill withdraws and passes the true amount as 'currentBalance'
    /// Keeper should be a contract so currentBalance and the call to the func happens atomically
    /// @param currentBalance is the amount of `asset` that is currently being used for strategy + the amount in the contract right before the roll
    public(friend) fun rollToNextRound(keeper: &signer, current_balance: u64) acquires Vault, VaultBalance, VaultState {
        let vault_params = borrow_global<Vault>(@stream);
        assert!(current_balance >= vault_params.minimum_supply, EINSUFFICIENT_BALANCE);
        let vault_state = borrow_global_mut<VaultState>(@stream);
        let current_round = vault_state.round;

        let new_price_per_share = shares_math::pricePerShare(
            totalSupply() - (vault_state.queued_withdraw_shares as u128),
            current_balance - vault_state.last_queued_withdraw_amount,
            vault_state.total_pending,
            (TOKEN_DECIMALS as u64),
        );

        smart_table::upsert(&mut vault_state.round_price_per_share, current_round, new_price_per_share);
        let prev_total_pending = vault_state.total_pending;
        vault_state.total_pending = 0;
        vault_state.round = current_round + 1;

        let mint_shares = shares_math::assetToShares(
            prev_total_pending,
            new_price_per_share,
            (TOKEN_DECIMALS as u64),
        );

        // Mint new vault shares
        let vault_balance = borrow_global_mut<VaultBalance>(@stream);
        let shares = coin::mint(mint_shares, &vault_balance.mint_cap);
        coin::merge(&mut vault_balance.unredeemed_shares, shares);

        let queued_withdraw_amount = vault_state.last_queued_withdraw_amount + shares_math::sharesToAsset(
            vault_state.current_queued_withdraw_shares,
            new_price_per_share,
            (TOKEN_DECIMALS as u64),
        );
        vault_state.last_queued_withdraw_amount = queued_withdraw_amount;

        vault_state.queued_withdraw_shares = vault_state.queued_withdraw_shares + vault_state.current_queued_withdraw_shares;
        vault_state.current_queued_withdraw_shares = 0;
        vault_state.last_locked_amount = vault_state.locked_amount;
        vault_state.locked_amount = current_balance - queued_withdraw_amount;

        let amount_to_keeper = coin::value(&vault_balance.balance) - queued_withdraw_amount;
        aptos_account::deposit_coins(
            signer::address_of(keeper),
            coin::extract(&mut vault_balance.balance, amount_to_keeper),
        );
    }

    /************************************************
     *  SETTERS
     ***********************************************/

    /// Transfers ownership of the vault to a new address
    /// @param new_owner is the new owner of the vault
    public entry fun transferOwnership(owner: &signer, new_owner: address) acquires VaultManagement {
        assert_is_owner(owner);
        let management = borrow_global_mut<VaultManagement>(@stream);
        management.owner = new_owner;
    }

    /// Sets the new keeper
    /// @param new_keeper is the address of the new keeper
    public entry fun setNewKeeper(owner: &signer, new_keeper: address) acquires VaultManagement {
        assert!(new_keeper != @0x0, EZERO_ADDRESS);
        assert_is_owner(owner);
        let management = borrow_global_mut<VaultManagement>(@stream);
        management.keeper = new_keeper;
    }

    /// Sets a new cap for deposits
    /// @param new_cap is the new cap for deposits
    public entry fun setCap(owner: &signer, new_cap: u64) acquires Vault, VaultManagement {
        assert!(new_cap > 0, EZERO_AMOUNT);
        assert_is_owner(owner);
        let vault = borrow_global_mut<Vault>(@stream);
        event::emit(CapSet {
            old_cap: vault.cap,
            new_cap,
        });
        vault.cap = new_cap;
    }

    /// Sets the new vault parameters
    public entry fun setVaultParameters(owner: &signer, minimum_supply: u64, cap: u64) acquires Vault, VaultManagement {
        assert_is_owner(owner);
        let vault = borrow_global_mut<Vault>(@stream);
        vault.minimum_supply = minimum_supply;
        vault.cap = cap;
    }

    /************************************************
     *  GETTERS
     ***********************************************/

    #[view]
    public fun vault_state(): (u64, u64, u64, u64, u64, u64, u64, u64) acquires VaultState {
        let vault_state = borrow_global<VaultState>(@stream);
        let curr_round_price_per_share = if (vault_state.round == 1) {
            0
        } else {
            *smart_table::borrow_with_default(&vault_state.round_price_per_share, vault_state.round - 1, &0)
        };
        (
            vault_state.round,
            vault_state.locked_amount,
            vault_state.last_locked_amount,
            vault_state.total_pending,
            vault_state.queued_withdraw_shares,
            vault_state.last_queued_withdraw_amount,
            vault_state.current_queued_withdraw_shares,
            curr_round_price_per_share,
        )
    }

    #[view]
    public fun keeper(): address acquires VaultManagement {
        borrow_global<VaultManagement>(@stream).keeper
    }

    #[view]
    public fun get_deposit_receipt(user: address): (u64, u64, u64) acquires VaultBalance {
        let deposit_receipt = deposit_receipt(user);
        (deposit_receipt.round, deposit_receipt.amount, deposit_receipt.unredeemed_shares)
    }

    #[view]
    public fun get_withdrawal(user: address): (u64, u64) acquires VaultBalance {
        let vault_balance = borrow_global<VaultBalance>(@stream);
        let withdrawal = smart_table::borrow_with_default(&vault_balance.withdrawals, user, &Withdrawal {
            // Default values of 0 to be as similar to Solidity code as possible
            round: 0,
            shares: 0,
        });
        (withdrawal.round, withdrawal.shares)
    }

    #[view]
    public fun total_unredeemed_shares(): u64 acquires VaultBalance {
        coin::value(&borrow_global<VaultBalance>(@stream).unredeemed_shares)
    }

    #[view]
    public fun total_withdraw_shares(): u64 acquires VaultBalance {
        coin::value(&borrow_global<VaultBalance>(@stream).withdrawal_shares)
    }

    #[view]
    public fun getCurrQueuedWithdrawAmount(current_balance: u64): u64 acquires VaultState {
        let vault_state = borrow_global<VaultState>(@stream);
        let new_price_per_share = shares_math::pricePerShare(
            totalSupply() - (vault_state.queued_withdraw_shares as u128),
            current_balance - vault_state.last_queued_withdraw_amount,
            vault_state.total_pending,
            (TOKEN_DECIMALS as u64),
        );
        vault_state.last_queued_withdraw_amount + shares_math::sharesToAsset(
            vault_state.current_queued_withdraw_shares,
            new_price_per_share,
            (TOKEN_DECIMALS as u64),
        )
    }

    #[view]
    public fun currentQueuedWithdrawShares(): u64 acquires VaultState {
        borrow_global<VaultState>(@stream).current_queued_withdraw_shares
    }

    #[view]
    public fun queuedWithdrawShares(): u64 acquires VaultState {
        borrow_global<VaultState>(@stream).queued_withdraw_shares
    }

    #[view]
    public fun lastLockedAmount(): u64 acquires VaultState {
        borrow_global<VaultState>(@stream).last_locked_amount
    }

    #[view]
    public fun lastQueuedWithdrawAmount(): u64 acquires VaultState {
        borrow_global<VaultState>(@stream).last_queued_withdraw_amount
    }

    #[view]
    public fun accountVaultBalance(account: address): u64 acquires VaultBalance, VaultState {
        let asset_per_share = shares_math::pricePerShare(
            totalSupply(),
            totalBalance(),
            borrow_global<VaultState>(@stream).total_pending,
            (TOKEN_DECIMALS as u64),
        );
        shares_math::sharesToAsset(shares(account), asset_per_share, (TOKEN_DECIMALS as u64))
    }

    #[view]
    public fun shares(account: address): u64 acquires VaultBalance, VaultState {
        let (held_by_account, held_by_vault) = shareBalances(account);
        held_by_account + held_by_vault
    }

    #[view]
    public fun shareBalances(account: address): (u64, u64) acquires VaultBalance, VaultState {
        let deposit_receipt = deposit_receipt(account);
        let balance = if (coin::is_account_registered<VaultToken>(account)) {
            coin::balance<VaultToken>(account)
        } else {
            0
        };
        if (deposit_receipt.round == 0) {
            return (balance, 0)
        };

        let vault_state = borrow_global<VaultState>(@stream);
        let round_price_per_share = *smart_table::borrow_with_default(&vault_state.round_price_per_share, deposit_receipt.round, &0);
        let unredeemed_shares = getSharesFromReceipt(
            deposit_receipt,
            vault_state.round,
            round_price_per_share,
        );
        (balance, unredeemed_shares)
    }

    #[view]
    public fun roundPricePerShare(round: u64): u64 acquires VaultState {
        let vault_state = borrow_global<VaultState>(@stream);
        *smart_table::borrow_with_default(&vault_state.round_price_per_share, round, &0)
    }

    #[view]
    public fun pricePerShare(): u64 acquires VaultBalance, VaultState {
        shares_math::pricePerShare(
            totalSupply(),
            totalBalance(),
            borrow_global<VaultState>(@stream).total_pending,
            (TOKEN_DECIMALS as u64),
        )
    }

    #[view]
    public fun totalSupply(): u128 {
        option::destroy_some(coin::supply<VaultToken>())
    }

    #[view]
    public fun totalBalance(): u64 acquires VaultBalance, VaultState {
        borrow_global<VaultState>(@stream).locked_amount + remainingBalance()
    }

    #[view]
    public fun remainingBalance(): u64 acquires VaultBalance {
        coin::value(&borrow_global<VaultBalance>(@stream).balance)
    }

    #[view]
    public fun lockedAmount(): u64 acquires VaultState {
        borrow_global<VaultState>(@stream).locked_amount
    }

    #[view]
    public fun decimals(): u8 {
        coin::decimals<VaultToken>()
    }

    #[view]
    public fun cap(): u64 acquires Vault {
        let vault = borrow_global<Vault>(@stream);
        vault.cap
    }

    #[view]
    public fun totalPending(): u64 acquires VaultState {
        borrow_global<VaultState>(@stream).total_pending
    }

    #[view]
    public fun round(): u64 acquires VaultState {
        borrow_global<VaultState>(@stream).round
    }

    /************************************************
     *  Private functions
     ***********************************************/

    inline fun assert_is_owner(owner: &signer) {
        let management = borrow_global<VaultManagement>(@stream);
        assert!(signer::address_of(owner) == management.owner, EUNAUTHORIZED);
    }

    /// Returns the shares unredeemed by the user given their DepositReceipt
    /// @param depositReceipt is the user's deposit receipt
    /// @param currentRound is the `round` stored on the vault
    /// @param assetPerShare is the price in asset per share
    /// @param decimals is the number of decimals the asset/shares use
    /// @return unredeemedShares is the user's virtual balance of shares that are owed
    fun getSharesFromReceipt(
        depositReceipt: &DepositReceipt,
        currentRound: u64,
        assetPerShare: u64,
    ): u64 {
        if (depositReceipt.round > 0 && depositReceipt.round < currentRound) {
            let sharesFromRound = shares_math::assetToShares(depositReceipt.amount, assetPerShare, (TOKEN_DECIMALS as u64));
            depositReceipt.unredeemed_shares + sharesFromRound
        } else {
            depositReceipt.unredeemed_shares
        }
    }

    fun transferAsset(user: address, amount: u64) acquires VaultBalance {
        let vault_balance = borrow_global_mut<VaultBalance>(@stream);
        aptos_account::deposit_coins(user, coin::extract(&mut vault_balance.balance, amount));
    }

    inline fun deposit_receipt(user: address): &DepositReceipt {
        let vault_balance = borrow_global<VaultBalance>(@stream);
        smart_table::borrow_with_default(&vault_balance.deposits, user, &DepositReceipt {
            // Default values of 0 to be as similar to Solidity code as possible
            round: 0,
            amount: 0,
            unredeemed_shares: 0,
        })
    }

    inline fun mut_deposit_receipt(user: address): &mut DepositReceipt {
        let vault_balance = borrow_global_mut<VaultBalance>(@stream);
        smart_table::borrow_mut_with_default(&mut vault_balance.deposits, user, DepositReceipt {
            // Default values of 0 to be as similar to Solidity code as possible
            round: 0,
            amount: 0,
            unredeemed_shares: 0,
        })
    }

    inline fun mut_withdrawal(user: address): &mut Withdrawal {
        let vault_balance = borrow_global_mut<VaultBalance>(@stream);
        smart_table::borrow_mut_with_default(&mut vault_balance.withdrawals, user, Withdrawal {
            // Default values of 0 to be as similar to Solidity code as possible
            round: 0,
            shares: 0,
        })
    }

    #[test_only]
    public fun init_for_test(stream_signer: &signer) {
        init_module(stream_signer);
    }

    #[test_only]
    friend stream::test_helpers;
}
