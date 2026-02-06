//! Minimal ERC20 interface for STRK transfer_from and transfer (no external dependency).

use core::integer::u256;
use starknet::ContractAddress;

#[starknet::interface]
pub trait IERC20<T> {
    fn transfer_from(ref self: T, sender: ContractAddress, recipient: ContractAddress, amount: u256)
        -> bool;
    fn transfer(ref self: T, recipient: ContractAddress, amount: u256) -> bool;
}
