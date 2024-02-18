#[allow(lint(self_transfer))]
module lottery::game {
    use lottery::drand_lib::{derive_randomness, verify_drand_signature, safe_selection};
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::clock::{Self, Clock};
    use std::option::{Self, Option};
    use std::vector;

    const EPaymentTooLow : u64 = 0;
    const EWrongLottery : u64 = 1;
    const ELotteryEnded: u64 = 2;
    const ELotteryNotEnded: u64 = 4;
    const ELotteryCompleted: u64 = 5;


    const ACTIVE : u64 = 0;
    const ENDED: u64 = 1;

    struct Lottery has key {
        id: UID,
        round: u64,
        endTime: u64,
        noOfTickets: u64,
        noOfPlayers: u32,
        winner: Option<address>,
        winningTicket: Option<u64>,
        ticketPrice: u64,
        reward: Balance<SUI>,
        status: u64,
        winnerClaimed: bool,
    }

    struct PlayerRecord has key, store {
        id: UID,
        lotteryId: ID,
        tickets: vector<u64>,
    }

    public fun startLottery(round: u64, ticketPrice: u64, lotteryDuration: u64, clock: &Clock, ctx: &mut TxContext) {
        // lotteryDuration is passed in minutes,
        let endTime = lotteryDuration + clock::timestamp_ms(clock);

        // create Lottery
        let lottery = Lottery {
            id: object::new(ctx),
            round,
            endTime,
            noOfTickets: 0,
            noOfPlayers: 0,
            winner: option::none(),
            winningTicket: option::none(),
            ticketPrice,
            reward: balance::zero(),
            status: ACTIVE, 
            winnerClaimed: false,
        };

        // make lottery accessible by everyone
        transfer::share_object(lottery);
    }

    public fun createPlayerRecord(lottery: &mut Lottery, ctx: &mut TxContext) {
        // get lottery id
        let lotteryId = object::uid_to_inner(&lottery.id);

        // create player record for lottery ID
        let player = PlayerRecord {
            id: object::new(ctx),
            lotteryId,
            tickets: vector::empty(),
        };

        lottery.noOfPlayers = lottery.noOfPlayers + 1;

        transfer::public_transfer(player, tx_context::sender(ctx));
    }

    // Anyone can buyticket after getting a playerRecord
    public fun buyTicket(lottery: &mut Lottery, playerRecord: &mut PlayerRecord, noOfTickets: u64, amount: Coin<SUI>, clock: &Clock ) {
        // check if user is calling from right lottery
        assert!(object::id(lottery) == playerRecord.lotteryId, EWrongLottery);

        // check that lottery has not ended
        assert!(lottery.endTime > clock::timestamp_ms(clock), ELotteryEnded);

        // check that lottery state is stil 0
        assert!(lottery.status == ACTIVE, ELotteryEnded);

        // calculate the total amount to be paid
        let amountRequired = lottery.ticketPrice * noOfTickets;

        // check that coin supplied is equal to the total amount required
        assert!(coin::value(&amount) >= amountRequired, EPaymentTooLow);

        // add the amount to the lottery's balance
        let coin_balance = coin::into_balance(amount);
        balance::join(&mut lottery.reward, coin_balance);

        // increment no of tickets bought and update players ticket record
        let oldTicketsCount = lottery.noOfTickets;
        let newTicketId = oldTicketsCount;
        let newTotal = oldTicketsCount + noOfTickets;
        while (newTicketId < newTotal) {
            vector::push_back(&mut playerRecord.tickets, newTicketId);
            newTicketId = newTicketId + 1;
        };

        lottery.noOfTickets = lottery.noOfTickets + noOfTickets;
    }

    // Anyone can end the lottery by providing the randomness of round.
    // randomness signature can be gotten from https://drand.cloudflare.com/52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971/public/<round>
    public fun endLottery(lottery: &mut Lottery, clock: &Clock, drand_sig: vector<u8>){
        // check that lottery has ended
        assert!(lottery.endTime < clock::timestamp_ms(clock), ELotteryNotEnded);

        // check that lottery state is stil 0
        assert!(lottery.status == ACTIVE, ELotteryEnded);

        verify_drand_signature(drand_sig, lottery.round);

        // The randomness is derived from drand_sig by passing it through sha2_256 to make it uniform.
        let digest = derive_randomness(drand_sig);

        lottery.winningTicket = option::some(safe_selection(lottery.noOfTickets, &digest));

        lottery.status = ENDED;
    }

    // Lottery Players can check if they won
    public fun checkIfWinner(lottery: &mut Lottery, player: PlayerRecord, ctx: &mut TxContext): bool {
        let PlayerRecord {id, lotteryId, tickets } = player;
        
        // check if user is calling from right lottery
        assert!(object::id(lottery) == lotteryId, EWrongLottery);

        // check that lottery state is ended
        assert!(lottery.status == ENDED, ELotteryNotEnded);

        // get winning ticket
        let winningTicket = option::borrow(&lottery.winningTicket);

        // check if winning ticket exists in lottery tickets
        let isWinner = vector::contains(&tickets, winningTicket);   

        if (isWinner){
            // check that winner has not claimed
            assert!(!lottery.winnerClaimed, ELotteryCompleted);
            // set user as winner
            lottery.winner = option::some(tx_context::sender(ctx));

            // get the reward
            let amount = balance::value(&lottery.reward);

            // wrap reward with coin
            let reward = coin::take(&mut lottery.reward, amount, ctx);
           
            transfer::public_transfer(reward, tx_context::sender(ctx));

            lottery.winnerClaimed = true ; 
        };
        
        // delete player record
        object::delete(id);

        isWinner
    }

    // Get player tickets
    public fun getPlayerTickets(playerRecord: &PlayerRecord): u64 {
        vector::length(&playerRecord.tickets)
    }

    // Get Winner
    public fun getWinner(lottery: &Lottery): Option<address> {
        lottery.winner
    }

    // Get ticket price
    public fun getTicketPrice(lottery: &Lottery): u64 {
        lottery.ticketPrice
    }

    // Tests
    #[test_only] use sui::test_scenario as ts;
    #[test_only] const Player1: address = @0xA;
    #[test_only] const Player2: address = @0xB;
    #[test_only] const Player3: address = @0xC;

    #[test_only]
    public fun testCreatePlayerRecord(ts: &mut ts::Scenario, sender: address){
        ts::next_tx(ts, sender);
        let lottery = ts::take_shared<Lottery>(ts);
        createPlayerRecord(&mut lottery, ts::ctx(ts));
        ts::return_shared(lottery);
    }

    #[test_only]
    public fun testBuyTickets(ts: &mut ts::Scenario, sender: address, noOfTickets: u64, clock: &Clock){
        ts::next_tx(ts, sender);
        let lottery = ts::take_shared<Lottery>(ts);
        let playerRecord = ts::take_from_sender<PlayerRecord>(ts);
        let ticketPrice = getTicketPrice(&lottery);
        let amountToPay = ticketPrice * noOfTickets;
        let amountCoin = coin::mint_for_testing<SUI>( amountToPay, ts::ctx(ts));
        buyTicket(&mut lottery, &mut playerRecord, noOfTickets, amountCoin, clock);
        ts::return_shared(lottery);
        ts::return_to_sender(ts, playerRecord);
    }

    #[test_only]
    public fun testCheckIfWinner(ts: &mut ts::Scenario, sender: address): bool {
        ts::next_tx(ts, sender);
        let lottery = ts::take_shared<Lottery>(ts);
        let playerRecord = ts::take_from_sender<PlayerRecord>(ts);
        let isWinner = checkIfWinner(&mut lottery, playerRecord, ts::ctx(ts));
        ts::return_shared(lottery);
        isWinner
    }

    #[test_only]
    public fun testConfirmWinner(ts: &mut ts::Scenario, sender: address) {
        ts::next_tx(ts, sender);
        let lottery = ts::take_shared<Lottery>(ts);
        let winner = getWinner(&lottery);
        assert!(option::contains(&winner, &sender) == true, 0);
        ts::return_shared(lottery);
    }

    #[test_only]
    public fun testConfirmNotWinner(ts: &mut ts::Scenario, sender: address) {
        ts::next_tx(ts, sender);
        let lottery = ts::take_shared<Lottery>(ts);
        let winner = getWinner(&lottery);
        assert!(option::contains(&winner, &sender) == false, 0);
        ts::return_shared(lottery);
    }

    #[test]
    fun test_lottery_game(){
        let ts = ts::begin(@0x0);
        let clock = clock::create_for_testing(ts::ctx(&mut ts));

        // start lottery
        {
            ts::next_tx(&mut ts, @0x0);

            let round: u64 = 1;
            let ticketPrice: u64 = 2; // 2 sui
            let lotteryDuration: u64 = 50; // 50 ticks

            startLottery(round, ticketPrice, lotteryDuration, &clock, ts::ctx(&mut ts));
        };

        // create player records for player1, player2 and player3 and buy tickets
        {
            testCreatePlayerRecord(&mut ts, Player1);
            testCreatePlayerRecord(&mut ts, Player2);
            testCreatePlayerRecord(&mut ts, Player3);
        };

        // buy tickets for player1, player2, player3
        {
            testBuyTickets(&mut ts, Player1, 30, &clock);
            testBuyTickets(&mut ts, Player2, 20, &clock);
            testBuyTickets(&mut ts, Player3, 10, &clock);
        };

        // increase time to lottery end
        {
            clock::increment_for_testing(&mut clock, 55);
        };

        // end lottery
        {
            ts::next_tx(&mut ts, @0x0);
            let lottery = ts::take_shared<Lottery>(&ts);

            // randomness signature can be gotten from https://drand.cloudflare.com/52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971/public/<round>
            // in this case ->  https://drand.cloudflare.com/52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971/public/1

            let drandSignature: vector<u8> = x"b55e7cb2d5c613ee0b2e28d6750aabbb78c39dcc96bd9d38c2c2e12198df95571de8e8e402a0cc48871c7089a2b3af4b";

            endLottery(&mut lottery, &clock, drandSignature );
            ts::return_shared(lottery);
        };

        // check winners for player 1, 2 and 3 and confirm
        {
            testCheckIfWinner(&mut ts, Player1);
            testCheckIfWinner(&mut ts, Player2);
            testCheckIfWinner(&mut ts, Player3);

            //confirm winner
            testConfirmWinner(&mut ts, Player1);
            testConfirmNotWinner(&mut ts, Player2);
            testConfirmNotWinner(&mut ts, Player3);

        };

        clock::destroy_for_testing(clock);
        ts::end(ts);
    }

    #[test]
    #[expected_failure]
    fun cannot_claim_twice(){
        let ts = ts::begin(@0x0);
        let clock = clock::create_for_testing(ts::ctx(&mut ts));

        // start lottery
        {
            ts::next_tx(&mut ts, @0x0);

            let round: u64 = 1;
            let ticketPrice: u64 = 2; // 2 sui
            let lotteryDuration: u64 = 50; // 50 ticks

            startLottery(round, ticketPrice, lotteryDuration, &clock, ts::ctx(&mut ts));
        };

        // create player records for player1, player2 and player3 and buy tickets
        {
            testCreatePlayerRecord(&mut ts, Player1);
            testCreatePlayerRecord(&mut ts, Player2);
            testCreatePlayerRecord(&mut ts, Player3);
        };

        // buy tickets for player1, player2, player3
        {
            testBuyTickets(&mut ts, Player1, 30, &clock);
            testBuyTickets(&mut ts, Player2, 20, &clock);
            testBuyTickets(&mut ts, Player3, 10, &clock);
        };

        // increase time to lottery end
        {
            clock::increment_for_testing(&mut clock, 55);
        };

        // end lottery
        {
            ts::next_tx(&mut ts, @0x0);
            let lottery = ts::take_shared<Lottery>(&ts);

            // randomness signature can be gotten from https://drand.cloudflare.com/52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971/public/<round>
            // in this case ->  https://drand.cloudflare.com/52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971/public/1

            let drandSignature: vector<u8> = x"b55e7cb2d5c613ee0b2e28d6750aabbb78c39dcc96bd9d38c2c2e12198df95571de8e8e402a0cc48871c7089a2b3af4b";

            endLottery(&mut lottery, &clock, drandSignature );
            ts::return_shared(lottery);
        };

        // check winners for player 1, 2 and 3 and confirm
        {
            testCheckIfWinner(&mut ts, Player1);           
        };

        // try to claim again
        {
            testCheckIfWinner(&mut ts, Player1);           
        };

        clock::destroy_for_testing(clock);
        ts::end(ts);
    }


    #[test]
    fun can_buy_multiple_tickets(){
        let ts = ts::begin(@0x0);
        let clock = clock::create_for_testing(ts::ctx(&mut ts));

        // start lottery
        {
            ts::next_tx(&mut ts, @0x0);

            let round: u64 = 1;
            let ticketPrice: u64 = 2; // 2 sui
            let lotteryDuration: u64 = 50; // 50 ticks

            startLottery(round, ticketPrice, lotteryDuration, &clock, ts::ctx(&mut ts));
        };

        // create player records for player1, player2 and player3 and buy tickets
        {
            testCreatePlayerRecord(&mut ts, Player1);
            testCreatePlayerRecord(&mut ts, Player2);
            testCreatePlayerRecord(&mut ts, Player3);
        };

        // buy tickets for player1, player2, player3
        {
            testBuyTickets(&mut ts, Player1, 30, &clock);
            testBuyTickets(&mut ts, Player2, 20, &clock);
            testBuyTickets(&mut ts, Player3, 10, &clock);

            testBuyTickets(&mut ts, Player2, 20, &clock);
            testBuyTickets(&mut ts, Player3, 30, &clock);
        };

        
        clock::destroy_for_testing(clock);
        ts::end(ts);
    }

    #[test]
    #[expected_failure]
    fun cannot_buy_ticket_after_time_elapses(){
        let ts = ts::begin(@0x0);
        let clock = clock::create_for_testing(ts::ctx(&mut ts));

        // start lottery
        {
            ts::next_tx(&mut ts, @0x0);

            let round: u64 = 1;
            let ticketPrice: u64 = 2; // 2 sui
            let lotteryDuration: u64 = 50; // 50 ticks

            startLottery(round, ticketPrice, lotteryDuration, &clock, ts::ctx(&mut ts));
        };

        // create player records for player1, player2 and player3 and buy tickets
        {
            testCreatePlayerRecord(&mut ts, Player1);
            testCreatePlayerRecord(&mut ts, Player2);
            testCreatePlayerRecord(&mut ts, Player3);
        };

        // buy tickets for player1, player2, player3
        {
            testBuyTickets(&mut ts, Player1, 30, &clock);
            testBuyTickets(&mut ts, Player2, 20, &clock);
            testBuyTickets(&mut ts, Player3, 10, &clock);
        };

        // increase time to lottery end
        {
            clock::increment_for_testing(&mut clock, 55);
        };

        // buy tickets for player1, player2, player3 after lottery ends
        {
            testBuyTickets(&mut ts, Player1, 30, &clock);
            testBuyTickets(&mut ts, Player2, 20, &clock);
            testBuyTickets(&mut ts, Player3, 10, &clock);
        };
        
        clock::destroy_for_testing(clock);
        ts::end(ts);
    }

}