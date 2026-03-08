pub mod systems {
    pub mod actions;
    pub mod buy_coins;
    pub mod claim_coins;
    pub mod end_run;
    pub mod init_game;
    pub mod initialize_coin_shop;
    pub mod pause_unpause_purchasing;
    pub mod purchase_cosmetic;
    pub mod purchase_mini_me_sessions;
    pub mod purchase_mini_me_unit;
    pub mod spend_coins;
    pub mod spend_revive;
    pub mod submit_leaderboard;
    pub mod update_exchange_rate;
}

pub mod coin_shop_config;
pub mod erc20;
pub mod rank_config;
pub mod rank_nft_contract;
pub mod models;
pub mod owner_access;
pub mod token_validation;

pub mod tests {
    mod test_coin_shop;
    mod test_systems_integration;
    mod test_world;
}
