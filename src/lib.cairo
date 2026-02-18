pub mod systems {
    pub mod actions;
    pub mod buy_coins;
    pub mod claim_coins;
    pub mod end_run;
    pub mod init_game;
    pub mod initialize_coin_shop;
    pub mod pause_unpause_purchasing;
    pub mod purchase_cosmetic;
    pub mod spend_coins;
    pub mod submit_leaderboard;
    pub mod update_exchange_rate;
}

pub mod erc20;
pub mod models;
pub mod owner_access;
pub mod token_validation;

pub mod tests {
    mod test_coin_shop;
    mod test_systems_integration;
    mod test_world;
}
