// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.15;

import {ISuperfluid, ISuperToken} from "protocol-monorepo/packages/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {IcfaV1Forwarder} from "../src/interfaces/IcfaV1Forwarder.sol";
import {TapWizard} from "../src/TapWizard.sol";
import {Tap} from "../src/Tap.sol";
import "forge-std/Script.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");
        IcfaV1Forwarder forwarder = IcfaV1Forwarder(vm.envAddress("CFAV1_FORWARDER_ADDRESS"));
        ISuperfluid host = ISuperfluid(vm.envAddress("SF_HOST_ADDRESS"));
        vm.startBroadcast(deployerPK);

        Tap tapImplementation = new Tap();
        TapWizard tapWizard = new TapWizard(
            forwarder,
            host,
            address(tapImplementation)
        );

        vm.stopBroadcast();
    }
}
