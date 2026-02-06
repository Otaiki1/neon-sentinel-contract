//! Owner access control: immutable owner check for admin functions.

use starknet::ContractAddress;

pub trait IsOwnerTrait {
    fn is_owner(caller: ContractAddress, owner: ContractAddress) -> bool;
}

impl IsOwner of IsOwnerTrait {
    fn is_owner(caller: ContractAddress, owner: ContractAddress) -> bool {
        caller == owner
    }
}
