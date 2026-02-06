//! ERC20 interface for STRK token interaction on Starknet.
//! STRK uses 18 decimals (1 STRK = 10^18 units).
//! Use transfer_from for user → contract; user must approve() first.

use core::integer::u256;
use starknet::ContractAddress;

/// STRK decimals (1 STRK = 10^18).
const STRK_DECIMALS: u8 = 18;

#[starknet::interface]
pub trait IERC20<T> {
    fn transfer(ref self: T, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: T,
        sender: ContractAddress,
        recipient: ContractAddress,
        amount: u256,
    ) -> bool;
    fn approve(ref self: T, spender: ContractAddress, amount: u256) -> bool;
    fn balance_of(ref self: T, account: ContractAddress) -> u256;
    fn allowance(ref self: T, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn total_supply(ref self: T) -> u256;
    fn decimals(ref self: T) -> u8;
}
