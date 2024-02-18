# SUI-DEFI_LOTTERY

Simple lottery contract

- It allows any player to be able to start the lottery, buy tickets and even end the lottery.
- Players can then check to see if they're the lucky winners of that lottery.
- Winner gets all of the prizepool.

The basic game depends on randomness from drand.

The quicknet chain chain of drand creates random 32 bytes every 3 seconds. This randomness is verifiable in the sense that anyone can check if a given 32 bytes bytes are indeed the i-th output of drand. For more details see [drand link](https://drand.love/).

NOTE: Running the test again for a round, provides the same set of results if the same set of inputs are passed in.

- For Example in test scenario, In round 1 with the given number of ticket buys we know that player 1 will be the winner because I had already ran it before. But if we were to change anything the result differs.

- Changing the round, changes the result, but you also need to update the signature

## Installation

To deploy and use the smart contract, follow these steps:

1. **Move Compiler Installation:**
   Ensure you have the Move compiler installed. You can find the Move compiler and instructions on how to install it at [Sui Docs](https://docs.sui.io/).

2. **Compile the Smart Contract:**
   For this contract to compile successfully, please ensure you switch the dependencies to whichever you installed. 
`framework/devnet` for Devnet, `framework/testnet` for Testnet

```bash
   Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "framework/devnet" }
```

then build the contract by running

```
sui move build
```

3. **Deployment:**
   Deploy the compiled smart contract to your blockchain platform of choice.

```
sui client publish --gas-budget 100000000 --json
```
