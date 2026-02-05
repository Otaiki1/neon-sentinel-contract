pub mod systems {
    pub mod actions;
    pub mod claim_coins;
    pub mod end_run;
    pub mod execute_tick;
    pub mod hit_registration;
    pub mod init_game;
    pub mod spend_coins;
    pub mod submit_leaderboard;
}

pub mod models;

pub mod tests {
    mod test_systems_integration;
    mod test_world;
}
