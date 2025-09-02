// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract TokenFactory {
    event TokenDeployed(address tokenAddress);
    uint256 public fee;

    address payable public Owner ;

    constructor(address payable  _owner, uint256 _service_fee){
        Owner = _owner;
        fee = _service_fee; // service fee for the token creation
    }
    
    modifier onlyOwner() {
        require(msg.sender == Owner, "Not owner");
        _;
    }

    function createToken(
        address target,
         address _owner,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _initialSupply,
        uint256 _maxSupply,
        bool _isBurnable,
        bool _isPausable
    ) external payable  returns (address result) {
        require(msg.value >= fee, "Insufficient Amount to Pay");
        Owner.transfer(msg.value);
        bytes20 targetBytes = bytes20(target);
        
        assembly {
            let clone := mload(0x40)
            mstore(
                clone,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )
            mstore(add(clone, 0x14), targetBytes)
            mstore(
                add(clone, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )
            result := create(0, clone, 0x37)
        }

        // Initialize the newly created contract
        bytes memory data = abi.encodeWithSignature(
            "initialize(address,string,string,uint8,uint256,uint256,bool,bool)",
             _owner,
             _name,
             _symbol,
             _decimals,
             _initialSupply,
             _maxSupply,
             _isBurnable,
             _isPausable
        );

        (bool success,) = result.call(data);
        require(success, "Initialization failed");

        emit TokenDeployed(result);
    }

        function _transferOwnership(address payable  _newOwner) public onlyOwner{
            Owner = _newOwner;
    }

        function setFee(uint256 newFee) public  onlyOwner {
        fee = newFee;
    }
}


