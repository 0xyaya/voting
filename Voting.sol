// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

contract Voting is Ownable {
    struct Voter {
        bool isRegistered;
        bool hasVoted;
        uint256 votedProposalId;
    }

    struct Proposal {
        string description;
        uint256 voteCount;
    }

    enum WorkflowStatus {
        RegisteringVoters,
        ProposalsRegistrationStarted,
        ProposalsRegistrationEnded,
        VotingSessionStarted,
        VotingSessionEnded,
        VotesTallied
    }

    event VoterRegistered(address voterAddress);
    event WorkflowStatusChange(
        WorkflowStatus previousStatus,
        WorkflowStatus newStatus
    );
    event ProposalRegistered(uint256 proposalId);
    event Voted(address voter, uint256 proposalId);

    uint256 public winningProposalId;
    uint256 public sessionNumber; // this number allow multiple votes with the double mapping voters
    WorkflowStatus public votingStatus;

    mapping(address => mapping(uint256 => Voter)) voters; // double mapping to allow multiple votes
    Proposal[] proposals;
    Proposal[] exaequo;

    modifier isRegistered(address _addr) {
        // We only use the first index here to register addresses once
        require(voters[_addr][0].isRegistered, "Address not registered!");
        _;
    }

    modifier hasntVoted(address _addr) {
        require(
            !voters[_addr][sessionNumber].hasVoted,
            "Address already voted."
        );
        _;
    }

    modifier requiredStatus(WorkflowStatus _status) {
        require(votingStatus == _status, "You can't do this now.");
        _;
    }

    constructor() {
        votingStatus = WorkflowStatus.RegisteringVoters;
        sessionNumber = 0;
    }

    // Usefull to change status and emit event
    function nextStatus() internal {
        WorkflowStatus previousStatus = votingStatus;
        votingStatus = WorkflowStatus(uint256(votingStatus) + 1);
        emit WorkflowStatusChange(previousStatus, votingStatus);
    }

    function vote(uint256 _proposalId)
        public
        isRegistered(msg.sender)
        hasntVoted(msg.sender)
        requiredStatus(WorkflowStatus.VotingSessionStarted)
    {
        require(_proposalId < proposals.length, "Bad proposalId.");
        voters[msg.sender][sessionNumber].votedProposalId = _proposalId;
        voters[msg.sender][sessionNumber].hasVoted = true;
        proposals[_proposalId].voteCount += 1;
        emit Voted(msg.sender, _proposalId);
    }

    function getVoter(address _addr, uint256 _session)
        public
        view
        isRegistered(msg.sender)
        returns (Voter memory)
    {
        return voters[_addr][_session];
    }

    /*
     * This function compute the proposal winner
     * Else we start the vote again with all the exaequo proposals
     */
    function computeWinningProposal()
        public
        requiredStatus(WorkflowStatus.VotingSessionEnded)
        onlyOwner
    {
        uint256 maxVote = proposals[0].voteCount;
        uint256 winnerId = 0;

        delete exaequo;
        exaequo.push(proposals[0]);

        for (uint256 i = 1; i < proposals.length; i++) {
            Proposal storage currentProposal = proposals[i];

            if (currentProposal.voteCount > maxVote) {
                delete exaequo; // The currentProposal is the temporary winner so no axaequo anymore we have to clean the array
                exaequo.push(currentProposal); // We push the temporary winner for maybe a futur exaequo array
                winnerId = i; // We keep the winner proposal index as Id
            } else if (currentProposal.voteCount == maxVote) {
                exaequo.push(currentProposal); // The last best proposal is now exaequo with this currentProposal
            }
        }

        // In this case we have to start again the vote
        if (exaequo.length > 1) {
            sessionNumber += 1; // Increment the sessionNumber to allow an other vote
            proposals = exaequo; // We save the exaequo proposals for the new vote session
            delete exaequo;
            votingStatus = WorkflowStatus.VotingSessionStarted;
            emit WorkflowStatusChange(
                WorkflowStatus.VotingSessionEnded,
                WorkflowStatus.VotingSessionStarted
            );
            return;
        }

        winningProposalId = winnerId;
        nextStatus();
    }

    function startNewSession()
        public
        requiredStatus(WorkflowStatus.VotesTallied)
        onlyOwner
    {
        delete proposals;
        sessionNumber += 1;
        votingStatus = WorkflowStatus.RegisteringVoters;
    }

    function registerProposal(string memory description)
        public
        isRegistered(msg.sender)
        requiredStatus(WorkflowStatus.ProposalsRegistrationStarted)
    {
        Proposal memory _proposal = Proposal(description, 0);
        proposals.push(_proposal);
        emit ProposalRegistered(proposals.length - 1);
    }

    function winningProposalDetails()
        public
        view
        requiredStatus(WorkflowStatus.VotesTallied)
        returns (Proposal memory)
    {
        return proposals[winningProposalId];
    }

    // Whitelist address to create proposals and vote
    function register(address _adr)
        public
        requiredStatus(WorkflowStatus.RegisteringVoters)
        onlyOwner
    {
        require(_adr != address(0), "You can't register this address!");
        require(!voters[_adr][0].isRegistered, "Address already registered!");
        voters[_adr][0].isRegistered = true;
    }

    function startProposalsRegistration()
        public
        requiredStatus(WorkflowStatus.RegisteringVoters)
        onlyOwner
    {
        nextStatus();
    }

    function endProposalsRegistration()
        public
        requiredStatus(WorkflowStatus.ProposalsRegistrationStarted)
        onlyOwner
    {
        require(
            proposals.length >= 1,
            "You can't end proposal registration without a proposal."
        );
        nextStatus();
    }

    function startVotingSession()
        public
        requiredStatus(WorkflowStatus.ProposalsRegistrationEnded)
        onlyOwner
    {
        nextStatus();
    }

    function endVotingSession()
        public
        requiredStatus(WorkflowStatus.VotingSessionStarted)
        onlyOwner
    {
        nextStatus();
    }
}
