### TLDR;
Claimable Superfluid token streams based on NFT possession.

# Introduction
NiftyTap allows anyone to distribute holders of an NFT collection to any number of Superfluid token streams. Imagine the creators of an NFT art collection who want to airdrop streams of tokens to their holders or a clever promoter who wants to promote his product by incentivising holders of an NFT collection. Maybe advertise to Lens profile holders or ENS domain holders? There are many more possibilities not even thought of yet!

# How Does It Work?
Anyone who wants to distribute some token using Superfluid constant flows can create a Tap using my smart contract. A tap is responsible for allowing a particular NFT collection's holders with claimable Superfluid streams. These streams are perpetual as long as the tap balance is maintained by the creator (of the tap). A holder can choose to claim any number of streams max up to the number of NFT token IDs they hold. Furthermore, if the holder transfers the NFT corresponding to which he claimed a stream, the new holder is eligible to claim a stream from a tap and the previous holder's streams will be adjusted accordingly.

# What's The Future Scope for NiftyTaps?
There are a bunch of things which can be done:

Integrate Stroller Protocol to earn a yield on idle assets and thereby increase tap balance.
Automate claims of streams so that they always go to the right holders at the right time using Gelato Network.
Add a stream-in feature so that the tap creator can top-up the balance of his tap using Superfluid streams.
Build conditional claims features which allow for claims only if certain conditions are satisfied either off-chain or on-chain.
Build a functional front-end for people to create these taps and holders to claim streams.
And many more!
