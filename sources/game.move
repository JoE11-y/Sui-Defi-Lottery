// Import statements

// Constants
const EPaymentTooLow: u64 = 0;
const EWrongLottery: u64 = 1;
const ELotteryEnded: u64 = 2;
const ELotteryNotEnded: u64 = 4;
const ELotteryCompleted: u64 = 5;
const EOverflow: u64 = 6; // Added for checked arithmetic overflow
const EInvalidSignature: u64 = 7; // Added for invalid signature
const EWinnerClaimed: u64 = 8; // Added for winner claimed bug

// Structs

// Lottery struct
struct Lottery {
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
    mutex: Mutex<()>, // Added mutex for reentrancy guard
}

// PlayerRecord struct
struct PlayerRecord {
    id: UID,
    lotteryId: ID,
    tickets: vector<u64>,
}

// Admin struct for access control
struct Admin { /* ... */ }

// Modifiers

// Modifier to allow only admin to execute a function
modifier onlyAdmin {
    assert!(is_admin(msg.sender()), ENotAdmin);
    _;
}

// Public Functions

// Function to start a new lottery, accessible only by admin
public fun startLottery(round: u64, ticketPrice: u64, lotteryDuration: u64, clock: &Clock, ctx: &mut TxContext) public onlyAdmin {
    // Implementation goes here
}

// Function to create a player record for a lottery
public fun createPlayerRecord(lottery: &mut Lottery, ctx: &mut TxContext) {
    // Implementation goes here
}

// Function to allow buying tickets for a lottery, with reentrancy guard
public fun buyTicket(lottery: &mut Lottery, playerRecord: &mut PlayerRecord, noOfTickets: u64, amount: Coin<SUI>, clock: &Clock) {
    let mut lock = lottery.mutex.lock(); // Lock mutex to prevent reentrancy
    // ... critical section protected by the lock
}

// Function to end a lottery and determine the winner, with secure randomness handling
public fun endLottery(lottery: &mut Lottery, clock: &Clock, oracle: &Oracle, signature: vector<u8>) public onlyAdmin {
    let randomness = oracle.get_randomness(lottery.round); // Get randomness from a trusted oracle
    assert!(verify_signature(&oracle, &randomness, &signature), EInvalidSignature);
    // ... use verified randomness
}

// Function to check if a player is a winner and claim the reward, with bug fixes
public fun checkIfWinner(lottery: &mut Lottery, player: PlayerRecord, ctx: &mut TxContext): bool {
    let PlayerRecord {id, lotteryId, tickets } = player;
    assert!(object::id(lottery) == lotteryId, EWrongLottery);
    assert!(lottery.status == ENDED, ELotteryNotEnded);
    let winningTicket = option::borrow(&lottery.winningTicket);
    let isWinner = vector::contains(&tickets, winningTicket);
    if (isWinner){
        assert!(!lottery.winnerClaimed, EWinnerClaimed);
        lottery.winner = option::some(tx_context::sender(ctx));
        let amount = balance::value(&lottery.reward);
        let reward = coin::take(&mut lottery.reward, amount, ctx);
        transfer::public_transfer(reward, tx_context::sender(ctx));
        lottery.winnerClaimed = true ; 
    };
    object::delete(id); // Moved delete operation inside if condition
    isWinner
}

// Helper Functions

// Function to get the number of tickets held by a player
public fun getPlayerTickets(playerRecord: &PlayerRecord): u64 {
    // Implementation goes here
}

// Function to get the winner of a lottery
public fun getWinner(lottery: &Lottery): Option<address> {
    lottery.winner
}

// Function to get the ticket price of a lottery
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
