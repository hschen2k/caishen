pragma solidity 0.4.18;

import "zeppelin-solidity/contracts/math/SafeMath.sol";
import "zeppelin-solidity/contracts/ownership/Ownable.sol";

// There are two planted security bugs in this contract.
// The SHA256 hash of the original contract is:
// abe7bc1b628cc9a17335d6ecce32a48e033f2479e931edcde782c68c1e69cd66

contract BuggyContract is Ownable {
    struct Gift {
        bool exists;        // 0 Only true if this exists
        uint giftId;        // 1 The gift ID
        address giver;      // 2 The address of the giver
        address recipient;  // 3 The address of the recipient
        uint expiry;        // 4 The expiry datetime of the timelock as a
                            //   Unix timestamp
        uint amount;        // 5 The amount of ETH
        bool redeemed;      // 6 Whether the funds have already been redeemed
        string giverName;   // 7 The giver's name
        string message;     // 8 A message from the giver to the recipient
        uint timestamp;     // 9 The timestamp of when the gift was given
    }

    // Total fees gathered since the start of the contract or the last time
    // fees were collected, whichever is latest
    uint public feesGathered;

    // Each gift has a unique ID. If you increment this value, you will get
    // an unused gift ID.
    uint public nextGiftId;

    // recipientToGiftIds maps each recipient address to a list of giftIDs of
    // Gifts they have received.
    mapping (address => uint[]) public recipientToGiftIds;

    // giftIdToGift maps each gift ID to its associated gift.
    mapping (uint => Gift) public giftIdToGift;

    event Constructed (address indexed by, uint indexed amount);
    event DirectlyDeposited(address indexed from, uint indexed amount);
    event Gave (uint indexed giftId,
                address indexed giver,
                address indexed recipient,
                uint amount, uint expiry);
    event Redeemed (uint indexed giftId,
                    address indexed giver,
                    address indexed recipient,
                    uint amount);
    event CollectedAllFees (address indexed by, uint indexed amount);

    // Constructor
    function CaiShen() public payable {
        Constructed(msg.sender, msg.value);
    }

    // Fallback function which allows this contract to receive funds.
    function () public payable {
        // Sending ETH directly to this contract does nothing except log an
        // event.
        DirectlyDeposited(msg.sender, msg.value);
    }

    ////// Getter functions:

    function getGiftIdsByRecipient (address recipient) 
    public view returns (uint[]) {
        return recipientToGiftIds[recipient];
    }

    //// Contract functions:

    // Call this function while sending ETH to give a gift.
    // @recipient: the recipient's address
    // @expiry: the Unix timestamp of the expiry datetime.
    // @giverName: the name of the giver
    // @message: a personal message
    // Tested in test/test_give.js and test/TestGive.sol
    function give (address recipient, uint expiry, string giverName, string message)
    public payable returns (uint) {
        address giver = msg.sender;

        // Validate the giver address
        assert(giver != address(0));

        // The gift must be a positive amount of ETH
        uint amount = msg.value;
        require(amount > 0);
        
        // The expiry datetime must be in the future.
        // The possible drift is only 12 minutes.
        // See: https://consensys.github.io/smart-contract-best-practices/recommendations/#timestamp-dependence
        require(expiry > now);

        // The giver and the recipient must be different addresses
        require(giver != recipient);

        // The recipient must be a valid address
        require(recipient != address(0));

        // Make sure nextGiftId is 0 or positive, or this contract is buggy
        assert(nextGiftId >= 0);

        // Append the gift to the mapping
        recipientToGiftIds[recipient].push(nextGiftId);

        // Calculate the contract owner's fee
        uint feeTaken = fee(amount);
        assert(feeTaken >= 0);

        // Increment feesGathered
        feesGathered = SafeMath.add(feesGathered, feeTaken);

        // Shave off the fee
        uint amtGiven = SafeMath.sub(amount, feeTaken);
        assert(amtGiven > 0);

        // If a gift with this new gift ID already exists, this contract is buggy.
        assert(giftIdToGift[nextGiftId].exists == false);

        // Update the giftIdToGift mapping with the new gift
        giftIdToGift[nextGiftId] = 
            Gift(true, nextGiftId, giver, recipient, expiry, 
            amtGiven, false, giverName, message, now);

        uint giftId = nextGiftId;

        // Increment nextGiftId
        nextGiftId = SafeMath.add(giftId, 1);

        // If a gift with this new gift ID already exists, this contract is buggy.
        assert(giftIdToGift[nextGiftId].exists == false);

        // Log the event
        Gave(giftId, giver, recipient, amount, expiry);

        return giftId;
    }

    // Call this function to redeem a gift of ETH.
    // Tested in test/test_redeem.js
    function redeem (uint giftId, amount) public {
        // The giftID should be 0 or positive
        require(giftId >= 0);

        // The gift must exist and must not have already been redeemed
        require(isValidGift(giftIdToGift[giftId]));

        // The recipient must be the caller of this function
        address recipient = giftIdToGift[giftId].recipient;
        require(recipient == msg.sender);

        // The current datetime must be the same or after the expiry timestamp
        require(now >= giftIdToGift[giftId].expiry);

        //// If the following assert statements are triggered, this contract is
        //// buggy.

        // The amount must be positive because this is required in give()
        assert(amount > 0);

        // The giver must not be the recipient because this was asserted in give()
        address giver = giftIdToGift[giftId].giver;
        assert(giver != recipient);

        // Make sure the giver is valid because this was asserted in give();
        assert(giver != address(0));

        // Update the gift to mark it as redeemed, so that the funds cannot be
        // double-spent
        giftIdToGift[giftId].redeemed = true;

        // Transfer the funds
        recipient.transfer(amount);

        // Log the event
        Redeemed(giftId, giftIdToGift[giftId].giver, recipient, amount);
    }

    // Calculate the contract owner's fee
    // Tested in test/test_fee.js
    function fee (uint amount) public pure returns (uint) {
        if (amount <= 0.01 ether) {
            return 0;
        } else if (amount > 0.01 ether) {
            return SafeMath.div(amount, 100);
        }
    }

    // Transfer the fees collected thus far to the contract owner.
    // Tested in test/test_collect_fees.js
    function collectAllFees () public {
        // Store the fee amount in a temporary variable
        uint amount = feesGathered;

        // Make sure that the amount is positive
        require(amount > 0);

        // Set the feesGathered state variable to 0
        feesGathered = 0;

        // Make the transfer
        msg.sender.transfer(amount);

        CollectedAllFees(owner, amount);
    }

    // Returns true only if the gift exists and has not already been
    // redeemed
    function isValidGift(Gift gift) private pure returns (bool) {
        return gift.exists == true && gift.redeemed == false;
    }
}