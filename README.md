# Run unit tests
aptos move test

# Deploy in testnet or mainnet
1. Make sure the following info in the vault.move file are set correctly before deploying:
a. Vault token's information - name, symbol, decimals
b. Vault params - minimum supply, cap
c. CoinType of Vault's underlying token. You need to add a dependency 

2. Create a new account on Movement
```bash
aptos init --profile stream
```
a. Select custom for network
b. For network url, manually type in Movement's testnet API - https://aptos.testnet.suzuka.movementlabs.xyz/v1
c. Don't enter anything for faucet

3. Go to https://faucet.movementlabs.xyz/, choose Aptos Move, type in your created account address and click "Get Move"
You can verify your balance by going to https://explorer.movementlabs.xyz/account/0xa00dee9cf189f95e788df7a7d743b2c10355ec51d139598a1a62681488ba624d?network=testnet
replacing the address with your account address.

4. Deploy the managers package first which contains the contract for managing who's the managers (keepers) of the vaults.
```bash
aptos move publish --named-addresses stream_managers=stream --included-artifacts none --profile stream
```

5. Deploy the vault and vault keeper contracts with the following command:
```bash
aptos move publish --named-addresses stream=stream,stream_managers=stream --included-artifacts none --profile stream
```
Verify the code is there by going to https://explorer.movementlabs.xyz/account/0xa00dee9cf189f95e788df7a7d743b2c10355ec51d139598a1a62681488ba624d/modules?network=testnet
replacing the address with your account address.

6. Register the manager for the vault's ticker (0x1::aptos_coin::AptosCoin for the MOVE token). Make sure you have the manager profile already created
```bash
aptos move run --function-id stream::managers::addVault --args string:"0x1::aptos_coin::AptosCoin" address:stream address:manager_profile --profile stream
```

7. Vault can now be rolled forward by calling
```bash
aptos move run --function-id stream::vault_keeper::rollRound --args u64:balance --profile manager_profile
```

# Deploy multiple vault contracts
You can create multiple profiles using different names with aptos init --profile <profile_name>

# Upgrade contract
The same command used to publish the contract can be used to upgrade. Make sure you use the right profile to upgrade the right vault contract.
```bash
aptos move publish --named-addresses stream=stream,keeper=stream --included-artifacts none --profile stream
```
