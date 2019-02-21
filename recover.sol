pragma solidity ^0.5.4;

import {CentralizedArbitrator, Arbitrable, Arbitrator} from "./CentralizedArbitrator.sol";

contract recover is Arbitrable {
    
    // **************************** //
    // *    Contract variables    * //
    // **************************** //

    // Amount of choices to solve the dispute if needed.
    uint8 constant AMOUNT_OF_CHOICES = 2;

    // Enum relative to different periods in the case of a negotiation or dispute.
    enum Status {NoDispute, WaitingFinder, WaitingOwner, DisputeCreated, Resolved}
    // The different parties of the dispute.
    enum Party {Owner, Finder}
    // The different ruling for the dispute resolution.
    enum RulingOptions {NoRuling, OwnerWins, FinderWins}
        
    struct Good {
        address payable owner; // Owner of the good.
        uint rewardAmount; // Amount of the reward in ETH.
        address addressForEncryption; // Address used to encrypt the link of description.
        bytes descriptionLinkEncrypted; // Description link encrypted to chat/find the owner of the good (ex: IPFS URL encrypted with the description).
        uint[] claimIDs; // Collection of the claim to give back the good and get the reward.
        uint amountLocked; // Amount locked while a claim is accepted.
        uint timeoutLocked; // Timeout after which the finder can call the function `executePayment`.
        uint ownerFee; // Total fees paid by the owner of the good.
        uint disputeID; // If dispute exists, the ID of the dispute.
        Status status; // Status of the good relative to a dispute.
        bool exists; // Boolean to check if the good exists or not in the collection.
        
    }

    struct Owner {
        string description; // (optionnal) Public description of the owner (ENS, Twitter, Telegram...)
        bytes32[] goodIDs; // Owner collection of the goods.
    }

    struct Claim {
        bytes32 goodID; // Relation one-to-one with the good.
        address payable finder; // Address of the good finder.
        uint finderFee; // Total fees paid by the finder.
        bytes linkDescription; // Public link description to proof we find the good (ex: IPFS URL with the content).
        uint lastInteraction; // Last interaction for the dispute procedure.
    }
    
    mapping(address => Owner) public owners; // Collection of the owners.
    
    mapping(bytes32 => Good) public goods; // Collection of the goods.
    
    mapping(bytes32 => uint) public disputeIDtoClaimAcceptedID; // One-to-one relationship between the dispute and the claim accepted.
    
    Claim[] claims; // Collection of the claims.
    Arbitrator arbitrator; // Address of the arbitrator contract.
    bytes arbitratorExtraData; // Extra data to set up the arbitration.
    uint feeTimeout; // Time in seconds a party can take to pay arbitration fees before being considered unresponding and lose the dispute.
    mapping (uint => bytes32) public disputeIDtoGoodID; // One-to-one relationship between the dispute and the good.
    
    // **************************** //
    // *          Events          * //
    // **************************** //

    /** @dev To be emitted when meta-evidence is submitted.
     *  @param _metaEvidenceID Unique identifier of meta-evidence. Should be the `transactionID`.
     *  @param _evidence A link to the meta-evidence JSON that follows the ERC 1497 Evidence standard (https://github.com/ethereum/EIPs/issues/1497).
     */
    event MetaEvidence(uint indexed _metaEvidenceID, string _evidence);

    /** @dev Indicate that a party has to pay a fee or would otherwise be considered as losing.
     *  @param _transactionID The index of the transaction.
     *  @param _party The party who has to pay.
     */
    event HasToPayFee(uint indexed _transactionID, Party _party);

    /** @dev To be raised when evidence is submitted. Should point to the resource (evidences are not to be stored on chain due to gas considerations).
     *  @param _arbitrator The arbitrator of the contract.
     *  @param _evidenceGroupID Unique identifier of the evidence group the evidence belongs to.
     *  @param _party The address of the party submitting the evidence. Note that 0 is kept for evidences not submitted by any party.
     *  @param _evidence A link to an evidence JSON that follows the ERC 1497 Evidence standard (https://github.com/ethereum/EIPs/issues/1497).
     */
    event Evidence(Arbitrator indexed _arbitrator, uint indexed _evidenceGroupID, address indexed _party, string _evidence);

    /** @dev To be emitted when a dispute is created to link the correct meta-evidence to the disputeID.
     *  @param _arbitrator The arbitrator of the contract.
     *  @param _disputeID ID of the dispute in the Arbitrator contract.
     *  @param _metaEvidenceID Unique identifier of meta-evidence. Should be the transactionID.
     *  @param _evidenceGroupID Unique identifier of the evidence group that is linked to this dispute.
     */
    event Dispute(Arbitrator indexed _arbitrator, uint indexed _disputeID, uint _metaEvidenceID, uint _evidenceGroupID);

    /** @dev To be raised when a ruling is given.
     *  @param _arbitrator The arbitrator giving the ruling.
     *  @param _disputeID ID of the dispute in the Arbitrator contract.
     *  @param _ruling The ruling which was given.
     */
    event Ruling(Arbitrator indexed _arbitrator, uint indexed _disputeID, uint _ruling);
    
    // **************************** //
    // *    Contract functions    * //
    // *    Modifying the state   * //
    // **************************** //

    /** @dev Constructor.
     *  @param _arbitrator The arbitrator of the contract.
     *  @param _arbitratorExtraData Extra data for the arbitrator.
     *  @param _feeTimeout Arbitration fee timeout for the parties.
     */
    constructor (
        Arbitrator _arbitrator,
        bytes memory _arbitratorExtraData,
        uint _feeTimeout
    ) public {
        arbitrator = _arbitrator;
        arbitratorExtraData = _arbitratorExtraData;
        feeTimeout = _feeTimeout;
    }
    
    /** @dev Add good.
     *  @param _goodID The index of the good.
     *  @param _addressForEncryption Link to the meta-evidence.
     *  @param _descriptionLinkEncrypted Time after which a party can automatically execute the arbitrable transaction.
     *  @param _rewardAmount The recipient of the transaction.
     *  @param _timeoutLocked Timeout after which the finder can call the function `executePayment`.
     */
    function addGood(
        bytes32 _goodID,
        address _addressForEncryption,
        bytes memory _descriptionLinkEncrypted,
        uint _rewardAmount,
        uint _timeoutLocked
    ) public {
        require(goods[_goodID].exists == false, "The id must be not registered.");

        // Add the good in the collection.
        goods[_goodID] = Good({
            owner: msg.sender, // The owner of the good.
            rewardAmount: _rewardAmount, // The reward to find the good.
            addressForEncryption: _addressForEncryption, // Address used to encrypt the link descritpion.
            descriptionLinkEncrypted: _descriptionLinkEncrypted, // Description link encrypted to chat/find the owner of the good.
            claimIDs: new uint[](0), // Empty array. There is no claims at this moment.
            amountLocked: 0, // Amount locked is 0. This variable is setting when there an accepting claim.
            timeoutLocked: _timeoutLocked, // If the a claim is accepted, time while the amount is locked.
            ownerFee: 0,
            disputeID: 0,
            status: Status.NoDispute, // No dispute at this moment.
            exists: true // The good exists now.
        });

        // Add the good in the owner good collection.
        owners[msg.sender].goodIDs.push(_goodID);

        // Store the encrypted link in the meta-evidence.
        emit MetaEvidence(uint(_goodID), string(_descriptionLinkEncrypted));
    }
    
    /** @dev Change the address used to encrypt the description link and the description.
     *  @param _goodID The index of the good.
     *  @param _addressForEncryption Time after which a party can automatically execute the arbitrable transaction.
     *  @param _descriptionLinkEncrypted The recipient of the transaction.
     */
    function changeAddressAndDescriptionEncrypted(
        bytes32 _goodID,
        address _addressForEncryption, 
        bytes memory _descriptionLinkEncrypted
    ) public {
        Good memory good = goods[_goodID];
        
        require(msg.sender == good.owner, "Must be the owner of the good.");

        good.addressForEncryption = _addressForEncryption;
        good.descriptionLinkEncrypted = _descriptionLinkEncrypted;
    }
    
    /** @dev Change the reward amount of the good.
     *  @param _goodID The index of the good.
     *  @param _rewardAmount The amount of the reward for the good.
     */
    function changeRewardAmount(bytes32 _goodID, uint _rewardAmount) public {
        Good memory good = goods[_goodID];
        
        require(msg.sender == good.owner, "Must be the owner of the good.");

        good.rewardAmount = _rewardAmount;
    }
    
    /** @dev Change the reward amount of the good.
     *  @param _goodID The index of the good.
     *  @param _timeoutLocked Timeout after which the finder can call the function `executePayment`.
     */
    function changeTimeoutLocked(bytes32 _goodID, uint _timeoutLocked) public {
        Good memory good = goods[_goodID];
        
        require(msg.sender == good.owner, "Must be the owner of the good.");

        good.timeoutLocked = _timeoutLocked;
    }
    
    /** @dev Reset claims for a good.
     *  @param _goodID The ID of the good.
     */
    function resetClaims(bytes32 _goodID) public {
        Good memory good = goods[_goodID];
        
        require(msg.sender == good.owner, "Must be the owner of the good.");
        require(0 == good.amountLocked, "Must have no accepted claim ongoing.");
        
        good.claimIDs = new uint[](0);
    }
    
    /** @dev Claim a good.
     *  @param _goodID The index of the good.
     *  @param _finder The address of the finder.
     *  @param _linkDescription The link to the description of the good (optionnal).
     */
    function claim(bytes32 _goodID, address payable _finder, bytes memory _linkDescription) public {
        Good memory good = goods[_goodID];
        
        require(
            msg.sender == good.addressForEncryption, 
            "Must be the same address than the address used to encrypt the message."
        );
        
        claims.push(Claim({
            goodID: _goodID,
            finder: _finder,
            finderFee: 0,
            linkDescription: _linkDescription,
            lastInteraction: now
        }));
        good.claimIDs[good.claimIDs.length] = claims.length;
    }
    
    /** @dev Accept a claim a good.
     *  @param _goodID The index of the good.
     *  @param _claimID The index of the claim.
     */
    function acceptClaim(bytes32 _goodID, uint _claimID) payable public {
        Good memory good = goods[_goodID];

        require(good.rewardAmount <= msg.value, "The ETH amount must be equal or higher than the reward");

        good.amountLocked += msg.value;
        disputeIDtoClaimAcceptedID[_goodID] = _claimID;
    }
    
    /** @dev Accept a claim a good.
     *  @param _goodID The index of the good.
     *  @param _claimID The index of the claim .
     */
    function removeClaim(bytes32 _goodID, uint _claimID) public {
        Good memory good = goods[_goodID];
        
        require(claims[_claimID].goodID == _goodID, "The claim of the good must matched with the good.");
        require(
            0 == disputeIDtoClaimAcceptedID[_goodID], 
            "The claim must not be accepted"
        );
        delete disputeIDtoClaimAcceptedID[_goodID];
        delete claims[_claimID];
    }
    
    /** @dev Pay finder. To be called if the good has been returned.
     *  @param _goodID The index of the good.
     *  @param _amount Amount to pay in wei.
     */
    function pay(bytes32 _goodID, uint _amount) public {
        Good storage good = goods[_goodID];
        Claim storage goodClaim = claims[disputeIDtoClaimAcceptedID[_goodID]];

        require(good.owner == msg.sender, "The caller must be the owner of the good.");
        require(good.status == Status.NoDispute, "The transaction of the good can't be disputed.");
        require(
            _amount <= good.amountLocked, 
            "The amount paid has to be less than or equal to the amount locked."
        );

        // Checks-Effects-Interactions to avoid reentrancy.
        address payable finder = goodClaim.finder; // Address of the finder.

        finder.transfer(_amount); // Transfer the fund to the finder.
        good.amountLocked -= _amount;
        if (good.amountLocked == 0)
            delete disputeIDtoClaimAcceptedID[_goodID];
    }
    
    /** @dev Reimburse owner of the good. To be called if the good can't be fully returned.
     *  @param _goodID The index of the good.
     *  @param _amountReimbursed Amount to reimburse in wei.
     */
    function reimburse(bytes32 _goodID, uint _amountReimbursed) public {
        Good storage good = goods[_goodID];
        Claim storage goodClaim = claims[disputeIDtoClaimAcceptedID[_goodID]];

        require(goodClaim.finder == msg.sender, "The caller must be the finder of the good.");
        require(good.status == Status.NoDispute, "The transaction good can't be disputed.");
        require(
            _amountReimbursed <= good.amountLocked, 
            "The amount paid has to be less than or equal to the amount locked."
        );

        address payable owner = good.owner; // Address of the owner.

        owner.transfer(_amountReimbursed);

        good.amountLocked -= _amountReimbursed;
        if (good.amountLocked == 0)
            delete disputeIDtoClaimAcceptedID[_goodID];
    }

    /** @dev Transfer the transaction's amount to the finder if the timeout has passed.
     *  @param _goodID The index of the good.
     */
    function executeTransaction(bytes32 _goodID) public {
        Good storage good = goods[_goodID];
        Claim storage goodClaim = claims[disputeIDtoClaimAcceptedID[_goodID]];

        require(goodClaim.goodID == _goodID, "The claim of the good must matched with the good.");
        require(now - goodClaim.lastInteraction >= good.timeoutLocked, "The timeout has not passed yet.");
        require(good.status == Status.NoDispute, "The transaction of the good can't be disputed.");

        goodClaim.finder.transfer(good.amountLocked);
        good.amountLocked = 0;

        good.status = Status.Resolved;
    }


    /* Section of Negociation or Dispute Resolution */

    /** @dev Pay the arbitration fee to raise a dispute. To be called by the owner. UNTRUSTED.
     *  Note that the arbitrator can have createDispute throw, 
     *  which will make this function throw and therefore lead to a party being timed-out.
     *  This is not a vulnerability as the arbitrator can rule in favor of one party anyway.
     *  @param _goodID The index of the transaction.
     */
    function payArbitrationFeeByOwner(bytes32 _goodID) public payable {
        Good storage good = goods[_goodID];
        Claim storage goodClaim = claims[disputeIDtoClaimAcceptedID[_goodID]];

        uint arbitrationCost = arbitrator.arbitrationCost(arbitratorExtraData);

        require(
            good.status < Status.DisputeCreated, 
            "Dispute has already been created or because the transaction of the good has been executed."
        );
        require(goodClaim.goodID == _goodID, "The claim of the good must matched with the good.");
        require(msg.sender == good.owner, "The caller must be the owner of the good.");
        require(0 != disputeIDtoClaimAcceptedID[_goodID], "The claim of the good must be accepted.");

        good.ownerFee += msg.value;
        // Require that the total paid to be at least the arbitration cost.
        require(good.ownerFee >= arbitrationCost, "The owner fee must cover arbitration costs.");

        goodClaim.lastInteraction = now;
        // The finder still has to pay. This can also happen if he has paid, but arbitrationCost has increased.
        if (goodClaim.finderFee < arbitrationCost) {
            good.status = Status.WaitingFinder;
            emit HasToPayFee(uint(_goodID), Party.Finder);
        } else { // The finder has also paid the fee. We create the dispute
            raiseDispute(_goodID, arbitrationCost);
        }
    }

    /** @dev Pay the arbitration fee to raise a dispute. To be called by the finder. UNTRUSTED.
     *  Note that this function mirrors payArbitrationFeeByFinder.
     *  @param _goodID The index of the good.
     */
    function payArbitrationFeeByFinder(bytes32 _goodID) public payable {
        Good storage good = goods[_goodID];
        Claim storage goodClaim = claims[disputeIDtoClaimAcceptedID[_goodID]];
        uint arbitrationCost = arbitrator.arbitrationCost(arbitratorExtraData);

        require(
            good.status < Status.DisputeCreated, 
            "Dispute has already been created or because the transaction has been executed."
        );
        require(goodClaim.goodID == _goodID, "The claim of the good must matched with the good.");
        require(msg.sender == goodClaim.finder, "The caller must be the sender.");
        require(0 != disputeIDtoClaimAcceptedID[_goodID], "The claim of the good must be accepted.");

        goodClaim.finderFee += msg.value;
        // Require that the total pay at least the arbitration cost.
        require(goodClaim.finderFee >= arbitrationCost, "The finder fee must cover arbitration costs.");

        goodClaim.lastInteraction = now;

        // The owner still has to pay. This can also happen if he has paid, but arbitrationCost has increased.
        if (good.ownerFee < arbitrationCost) {
            good.status = Status.WaitingOwner;
            emit HasToPayFee(uint(_goodID), Party.Owner);
        } else { // The owner has also paid the fee. We create the dispute
            raiseDispute(_goodID, arbitrationCost);
        }
    }
    
    /** @dev Reimburse owner of the good if the finder fails to pay the fee.
     *  @param _goodID The index of the good.
     */
    function timeOutByOwner(bytes32 _goodID) public {
        Good storage good = goods[_goodID];
        Claim storage goodClaim = claims[disputeIDtoClaimAcceptedID[_goodID]];

        require(
            good.status == Status.WaitingFinder, 
            "The transaction of the good must waiting on the finder."
        );
        require(now - goodClaim.lastInteraction >= feeTimeout, "Timeout time has not passed yet.");
        
        executeRuling(_goodID, uint(RulingOptions.OwnerWins));
    }

    /** @dev Pay finder if owner of the good fails to pay the fee.
     *  @param _goodID The index of the good.
     */
    function timeOutByFinder(bytes32 _goodID) public {
        Good storage good = goods[_goodID];
        Claim storage goodClaim = claims[disputeIDtoClaimAcceptedID[_goodID]];

        require(
            good.status == Status.WaitingOwner, 
            "The transaction of the good must waiting on the owner of the good."
        );
        require(now - goodClaim.lastInteraction >= feeTimeout, "Timeout time has not passed yet.");

        executeRuling(_goodID, uint(RulingOptions.FinderWins));
    }

    /** @dev Create a dispute. UNTRUSTED.
     *  @param _goodID The index of the good.
     *  @param _arbitrationCost Amount to pay the arbitrator.
     */
    function raiseDispute(bytes32 _goodID, uint _arbitrationCost) internal {
        Good storage good = goods[_goodID];
        Claim storage goodClaim = claims[disputeIDtoClaimAcceptedID[_goodID]];

        good.status = Status.DisputeCreated;
        good.disputeID = arbitrator.createDispute.value(_arbitrationCost)(AMOUNT_OF_CHOICES, arbitratorExtraData);
        disputeIDtoGoodID[good.disputeID] = _goodID;
        emit Dispute(arbitrator, good.disputeID, uint(_goodID), uint(_goodID));

        // Refund finder if it overpaid.
        if (goodClaim.finderFee > _arbitrationCost) {
            uint extraFeeFinder = goodClaim.finderFee - _arbitrationCost;
            goodClaim.finderFee = _arbitrationCost;
            goodClaim.finder.send(extraFeeFinder);
        }

        // Refund owner if it overpaid.
        if (good.ownerFee > _arbitrationCost) {
            uint extraFeeOwner = good.ownerFee - _arbitrationCost;
            good.ownerFee = _arbitrationCost;
            good.owner.send(extraFeeOwner);
        }
    }

    /** @dev Submit a reference to evidence. EVENT.
     *  @param _goodID The index of the good.
     *  @param _evidence A link to an evidence using its URI.
     */
    function submitEvidence(bytes32 _goodID, string memory _evidence) public {
        Good storage good = goods[_goodID];
        Claim storage goodClaim = claims[disputeIDtoClaimAcceptedID[_goodID]];

        require(
            msg.sender == good.owner || msg.sender == goodClaim.finder, 
            "The caller must be the owner of the good or the finder."
        );

        require(good.status >= Status.DisputeCreated, "The dispute has not been created yet.");
        emit Evidence(arbitrator, uint(_goodID), msg.sender, _evidence);
    }

    /** @dev Appeal an appealable ruling.
     *  Transfer the funds to the arbitrator.
     *  Note that no checks are required as the checks are done by the arbitrator.
     *  @param _goodID The index of the good.
     */
    function appeal(bytes32 _goodID) public payable {
        arbitrator.appeal.value(msg.value)(goods[_goodID].disputeID, arbitratorExtraData);
    }

    /** @dev Give a ruling for a dispute. Must be called by the arbitrator.
     *  The purpose of this function is to ensure that the address calling it has the right to rule on the contract.
     *  @param _disputeID ID of the dispute in the Arbitrator contract.
     *  @param _ruling Ruling given by the arbitrator. Note that 0 is reserved for "Not able/wanting to make a decision".
     */
    function rule(uint _disputeID, uint _ruling) public {
        bytes32 goodID = disputeIDtoGoodID[_disputeID];

        require(msg.sender == address(arbitrator), "The caller must be the arbitrator.");
        require(goods[goodID].status == Status.DisputeCreated, "The dispute has already been resolved.");

        emit Ruling(Arbitrator(msg.sender), _disputeID, _ruling);

        executeRuling(goodID, _ruling);
    }

    /** @dev Execute a ruling of a dispute. It reimburses the fee to the winning party.
     *  @param _goodID The index of the good.
     *  @param _ruling Ruling given by the arbitrator. 1 : Reimburse the owner of the good. 2 : Pay the finder.
     */
    function executeRuling(bytes32 _goodID, uint _ruling) internal {
        Good storage good = goods[_goodID];
        require(_ruling <= AMOUNT_OF_CHOICES, "Invalid ruling.");
        Claim storage goodClaim = claims[disputeIDtoClaimAcceptedID[_goodID]];

        // Give the arbitration fee back.
        // Note that we use send to prevent a party from blocking the execution.
        if (_ruling == uint(RulingOptions.OwnerWins)) {
            good.owner.send(good.ownerFee + good.amountLocked);
        } else if (_ruling == uint(RulingOptions.FinderWins)) {
            goodClaim.finder.send(goodClaim.finderFee + good.amountLocked);
        } else {
            uint split_amount = (good.ownerFee + good.amountLocked) / 2;
            good.owner.send(split_amount);
            goodClaim.finder.send(split_amount);
        }

        delete disputeIDtoClaimAcceptedID[_goodID];
        good.amountLocked = 0;
        good.ownerFee = 0;
        goodClaim.finderFee = 0;
        good.status = Status.Resolved;
    }
    
    // **************************** //
    // *     View functions       * //
    // **************************** //
    
    function isGoodExist(bytes32 _goodID) public view returns (bool) {
        return goods[_goodID].exists;
    }
}