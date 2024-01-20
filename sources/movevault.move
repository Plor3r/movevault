module movevault::movevault {
    use std::ascii::string;

    use sui::event::emit;
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID};
    use sui::transfer::{public_share_object, public_transfer};
    use std::option::{Self, Option};
    use sui::clock::{Self, Clock};
    use sui::table::{Self, Table};

    use smartinscription::movescription::{Self, Movescription};

    const EInvalidInscription: u64 = 0;
    const ENotEnabled: u64 = 1;
    const ENotClaimable: u64 = 2;
    const EMaxBalanceExceeded: u64 = 3;
    const EMaxPayoutsExceeded: u64 = 4;
    const ELessThanMinimumDeposit: u64 = 5;

    //Financial Model
    // 50M
    const MaxBalance: u64 = 50000000;
    // 10000+ deposits; will compound available rewards
    const MinimumDeposit: u64 = 10000;
    // 2.5M max claim daily, 10 days missed claims
    // const MaxAvailable: u64 = 2500000;
    // 125M
    const MaxPayouts: u64 = 125000000;
    const RatioPrecision: u64 = 10000;

    struct ManagerCap has key, store { id: UID }

    struct UserData has store {
        current_balance: u64,
        payouts: u64,
        deposits: u64,
        last_time: u64,
        rewards: u64,
    }

    struct ValutGame has key, store {
        id: UID,
        paused: bool,
        treasury_ratio: u64,
        extra_ratio: u64,
        min_deposit: u64,
        max_deposit_interval: u64,
        deposit_txs: u64,
        last_user: Option<address>,
        last_deposit_time: u64,
        reward_amount: u64,
        user_datas: Table<address, UserData>,
        collateral_treasury: Option<Movescription>,
        collateral_extra_pool: Option<Movescription>
    }

    // ======== Events ========
    struct Deposit has copy, drop {
        user: address,
        amount: u64
    }

    struct DepositReward has copy, drop {
        user: address,
        amount: u64
    }

    struct Claimed has copy, drop {
        user: address,
        amount: u64
    }

    // ======== init Functions =========

    fun init(ctx: &mut TxContext) {
        public_transfer(ManagerCap { id: object::new(ctx) }, tx_context::sender(ctx));
        public_share_object(ValutGame {
            id: object::new(ctx),
            paused: true,
            treasury_ratio: 400, // 4%
            extra_ratio: 9600, // 96%
            min_deposit: 10000,
            deposit_txs: 0,
            max_deposit_interval: 600000, // 10 minutes
            last_user: option::none(),
            last_deposit_time: 0,
            reward_amount: 0,
            user_datas: table::new(ctx),
            collateral_treasury: option::none(),
            collateral_extra_pool: option::none()
        });
    }

    fun new_user_data(): UserData {
        UserData {
            current_balance: 0,
            payouts: 0,
            deposits: 0,
            last_time: 0,
            rewards: 0,
        }
    }

    // Assert

    fun assert_enabled(vault_game: &ValutGame) {
        assert!(!vault_game.paused, ENotEnabled);
    }

    fun assert_valid_tick(inscription: &Movescription) {
        assert!(movescription::tick(inscription) == string(b"MOVE"), EInvalidInscription);
    }

    fun assert_valid_amount(inscription: &Movescription, required_minimum: u64) {
        assert!(movescription::amount(inscription) >= required_minimum, ELessThanMinimumDeposit);
    }

    // ======== Read Functions =========

    public fun paused(vault_game: &ValutGame): bool {
        vault_game.paused
    }

    public fun min_deposit(vault_game: &ValutGame): u64 {
        vault_game.min_deposit
    }

    public fun deposit_txs(vault_game: &ValutGame): u64 {
        vault_game.deposit_txs
    }

    public fun last_deposit_time(vault_game: &ValutGame): u64 {
        vault_game.last_deposit_time
    }

    public fun last_user(vault_game: &ValutGame): Option<address> {
        vault_game.last_user
    }

    public fun reward_amount(vault_game: &ValutGame): u64 {
        vault_game.reward_amount
    }

    // ======== Manage functions ========
    public entry fun set_pause(_: &ManagerCap, vault_game: &mut ValutGame, p: bool, _ctx: &mut TxContext) {
        vault_game.paused = p;
    }

    public entry fun set_treasury_ratio(_: &ManagerCap, vault_game: &mut ValutGame, ratio: u64, _ctx: &mut TxContext) {
        vault_game.treasury_ratio = ratio;
    }

    public entry fun set_extra_ratio(_: &ManagerCap, vault_game: &mut ValutGame, ratio: u64, _ctx: &mut TxContext) {
        vault_game.extra_ratio = ratio;
    }

    // ======== Deposit ========

    public entry fun deposit(
        vault_game: &mut ValutGame,
        inscription: Movescription,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert_enabled(vault_game);
        assert_valid_tick(&inscription);
        assert_valid_amount(&inscription, vault_game.min_deposit);

        let amount = movescription::amount(&inscription);
        let share = amount / RatioPrecision;

        let treasury_amount = share * share * vault_game.treasury_ratio;

        // deposit inscription into treasury
        let treasury_inscription = movescription::do_split(&mut inscription, treasury_amount, ctx);
        if (option::is_some(&vault_game.collateral_treasury)) {
            movescription::merge(option::borrow_mut(&mut vault_game.collateral_treasury), treasury_inscription);
        } else {
            option::fill(&mut vault_game.collateral_treasury, treasury_inscription);
        };
        // deposit inscription into extra pool
        if (option::is_some(&vault_game.collateral_extra_pool)) {
            movescription::merge(option::borrow_mut(&mut vault_game.collateral_extra_pool), inscription);
        } else {
            option::fill(&mut vault_game.collateral_extra_pool, inscription);
        };

        // update user data
        let sender = tx_context::sender(ctx);
        if (!table::contains(&vault_game.user_datas, sender)) {
            table::add(&mut vault_game.user_datas, sender, new_user_data());
        };
        let user_data = table::borrow_mut(&mut vault_game.user_datas, sender);
        deposit_internal(user_data, sender, amount, clock);

        // update global game data
        if (vault_game.last_deposit_time == 0 ||
            clock::timestamp_ms(clock) - vault_game.last_deposit_time < vault_game.max_deposit_interval) {
            // update winner
            vault_game.last_user = option::some(sender);
            vault_game.last_deposit_time = clock::timestamp_ms(clock);
            vault_game.reward_amount = movescription::amount(option::borrow(&vault_game.collateral_extra_pool)) / 2;
        };

        // update deposit info
        vault_game.deposit_txs = vault_game.deposit_txs + 1;
        if (vault_game.min_deposit < 100000 && vault_game.deposit_txs % 100 == 0) {
            vault_game.min_deposit = vault_game.min_deposit + 5000;
        };

        emit(Deposit { user: sender, amount: amount });
    }

    fun deposit_internal(user_data: &mut UserData, _user: address, amount: u64, clock: &Clock) {
        assert!(user_data.current_balance + amount <= MaxBalance, EMaxBalanceExceeded);
        assert!(user_data.payouts <= MaxPayouts, EMaxPayoutsExceeded);

        //if user has an existing balance see if we have to claim yield before proceeding
        //optimistically claim yield before reset
        //if there is a balance we potentially have yield
        // if (user_data.current_balance > 0) {
        //     compoundYield(user, user_data);
        // };

        //update user
        user_data.deposits = user_data.deposits + amount;
        user_data.last_time = clock::timestamp_ms(clock);
        user_data.current_balance = user_data.current_balance + amount;
    }

    public entry fun deposit_reward(
        vault_game: &mut ValutGame,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert_enabled(vault_game);

        let sender = tx_context::sender(ctx);
        if (!table::contains(&vault_game.user_datas, sender)) {
            table::add(&mut vault_game.user_datas, sender, new_user_data());
        };
        let user_data = table::borrow_mut(&mut vault_game.user_datas, sender);
        let rewards = user_data.rewards;
        assert!(rewards >= MinimumDeposit, ELessThanMinimumDeposit);
        deposit_internal(user_data, sender, rewards, clock);

        user_data.rewards = 0;

        emit(DepositReward { user: sender, amount: rewards });
    }

    // ======== Claim ========

    public fun jackpot_claimable(
        vault_game: &mut ValutGame,
        clock: &Clock
    ): bool {
        vault_game.last_deposit_time > 0 &&
            clock::timestamp_ms(clock) - vault_game.last_deposit_time >= vault_game.max_deposit_interval
    }

    public entry fun claim_jackpot(vault_game: &mut ValutGame, clock: &Clock, ctx: &mut TxContext) {
        assert_enabled(vault_game);
        assert!(jackpot_claimable(vault_game, clock), ENotClaimable);

        vault_game.last_deposit_time = 0;
        vault_game.min_deposit = 10000;
        vault_game.deposit_txs = 0;

        // option::is_some(&vault_game.last_user) && vault_game.reward_amount > 0
        // get winner and reset 
        let last_user = option::extract(&mut vault_game.last_user);
        let reward_amount = vault_game.reward_amount;
        vault_game.reward_amount = 0; // not necessary, but for insurance

        let inscription = movescription::do_split(
            option::borrow_mut(&mut vault_game.collateral_extra_pool),
            reward_amount,
            ctx
        );
        public_transfer(inscription, last_user);
        emit(Claimed { user: last_user, amount: reward_amount });
    }
}