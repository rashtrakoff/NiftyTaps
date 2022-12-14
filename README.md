### TL;DR

Claimable Superfluid token streams based on NFT possession.

# Introduction

NiftyTap allows anyone to distribute, to the holders of an NFT collection, any number of Superfluid token streams. Imagine the creators of an NFT art collection who want to airdrop streams of tokens to their holders or a clever promoter who wants to promote his product by incentivising holders of an NFT collection. Maybe advertise to Lens profile holders or ENS domain holders? There are many more possibilities not even thought of yet!

# How Does It Work?

Anyone who wants to distribute some token using Superfluid constant flows can create a Tap using my smart contract. A tap is responsible for allowing a particular NFT collection's holders with claimable Superfluid streams. These streams are perpetual as long as the tap balance is maintained by the creator (of the tap). A holder can choose to claim any number of streams max up to the number of NFT token IDs they hold. Furthermore, if the holder transfers the NFT corresponding to which he claimed a stream, the new holder is eligible to claim a stream from a tap and the previous holder's streams will be adjusted accordingly.

# What's The Future Scope for NiftyTaps?

There are a bunch of things which can be done:

- Integrate Stroller Protocol to earn a yield on idle assets and thereby increase tap balance.
- Automate claims of streams so that they always go to the right holders at the right time using Gelato Network.
- Add a stream-in feature so that the tap creator can top-up the balance of his tap using Superfluid streams.
- Build conditional claims features which allow for claims only if certain conditions are satisfied either off-chain or on-chain.
- Build a functional front-end for people to create these taps and holders to claim streams.

And many more!

# Deployments

| Chain           | Names                                                                                                                     |
|-----------------|---------------------------------------------------------------------------------------------------------------------------|
| Polygon Mumbai  | TapWizard: 0xfe5E4EEC148f1EE4172a87cfB89EADCcC79929ca<br>Tap (Implementation): 0xeF726f942F58D3ca2DCe0E0D076fdB9F4C05CD80 |
| Polygon Mainnet | TapWizard: 0x27Dcb9caED2Cd91430292916144de0D30D4A01E3<br>Tap (implementation): 0xE7D0f8C62Ab960888ECA61d9DF8bCFB69FD396c3 |

# How to Use the Contracts?

There are only two contracts you need to be concerned with; `TapWizard` and `Tap`. The `Tap` contract is NOT SUPPOSED to be directly deployed for usage. We use *Clones* library by OpenZeppelin to deploy a tap.

## Create a Tap

Use `createTap` method in the `TapWizard` contract and give the following arguments:

- `string memory _name` = Name of the tap. Shouldn't clash with an existing one. Only for novelty purpose.
- `uint96 _ratePerNFT` = Flow rate per claimed stream.
- `IERC721 _nft` = NFT contract address which allows for stream claims.
- `ISuperToken _streamToken` = The supertoken which will be disbursed by the tap.

`createTap` method returns an address for the newly deployed clone of `Tap` contract.

- Next, you will have to activate the tap by using the `activateTap` method in the recently deployed clone of tap. 
- Give enough allowance for the `Tap` clone to take super tokens from you in the next step.
- Top up the `Tap` clone contract by using `topUpTap` method in the clone. Ensure you have given enough allowance.
- Now it's ready for use!

## Deploy the Contracts

> Note: Fill the environment variables for these steps to make effect.

I am using forge script `Deploy.s.sol` for deploying the necessary contracts. This includes deploying a `Tap` contract for implementation instance which can be used in the `TapWizard` to create clones and the `TapWizard` contract itself. Please see the contract interfaces to understand the arguments to be passed. Run the below command to deploy the contracts.

``` bash
source .env
forge script script/Deploy.s.sol:DeployScript --rpc-url $MUMBAI_RPC_URL --broadcast -vvvv
```

## Verification of Contract

Using `--verify` flag while running `Deploy.s.sol` script throws some error. Try verifying the contracts independently using `forge verify-contract` command. To use environment variables, run `source .env` command.

The following command verifies the `Tap` implementation contract (on Mumbai testnet).

``` bash
forge verify-contract <Tap address> Tap --watch --chain-id 80001 $POLYGONSCAN_API_KEY
```

Verifying the `TapWizard` is a bit different. You will have to pass the constructor arguments. I use a `.txt` file created after deploying the contracts. Add the arguments passed to the `TapWizard` contract during deployment separated by a space then run the following command:

``` bash
forge verify-contract <TapWizard contract address> TapWizard --constructor-args-path < Path to .txt file> --watch --chain-id 80001 $POLYGONSCAN_API_KEY`
```

For any other help, please reach out to me using Discord (rashtrakoff#2547).
