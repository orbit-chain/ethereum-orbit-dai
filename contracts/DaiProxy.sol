pragma solidity ^0.5.0;

contract ReserveLike {
    function depositToken(address, address, uint, address) public;
}

contract WrappedDaiLike {
    uint public totalSupply;
    function approve(address, uint) public returns (bool);

    function mint(address, uint) public;
    function burn(address, uint) public;
}

contract DaiLike {
    function approve(address, uint) public returns (bool);
    function transferFrom(address, address, uint) public returns (bool);
}

contract JoinLike {
    VatLike public vat;
    DaiLike public dai;

    function join(address, uint) public;
    function exit(address, uint) public;
}

contract PotLike {
    mapping(address => uint) public pie;
    uint public chi;

    VatLike public vat;
    uint public rho;

    function drip() public returns (uint);

    function join(uint) public;
    function exit(uint) public;
}

contract VatLike {
    mapping(address => uint) public dai;

    function hope(address) public;
    function move(address, address, uint) public;
}

contract DaiProxy {
    string public constant version = "0303";

    // --- Owner ---
    address public owner;

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    event SetOwner(address owner);

    function setOwner(address _owner) public onlyOwner {
        owner = _owner;
        emit SetOwner(_owner);
    }

    // --- Paused ---
    bool public paused = false;

    modifier notPaused {
        require(!paused);
        _;
    }

    // 같은 EDai / ODai를 사용하는 새로운 Proxy가 생기면 켜야 함
    function setPaused(bool _paused) public onlyOwner {
        paused = _paused;
    }

    // --- Math ---
    uint constant ONE = 10 ** 27;

    function sub(uint a, uint b) private pure returns (uint) {
        require(a >= b);
        return a - b;
    }

    function mul(uint a, uint b) private pure returns (uint) {
        require(b == 0 || a <= uint(-1) / b);
        return a * b;
    }

    function div(uint a, uint b) private pure returns (uint) {
        require(b != 0);
        return a / b;
    }

    // --- Contracts & Constructor ---
    DaiLike public Dai;
    JoinLike public Join;
    PotLike public Pot;
    VatLike public Vat;

    ReserveLike public Reserve;

    WrappedDaiLike public EDai;
    WrappedDaiLike public ODai;

    constructor(address dai, address join, address pot, address vat, address eDai, address oDai) public {
        owner = msg.sender;

        Dai = DaiLike(dai);
        Join = JoinLike(join);
        Pot = PotLike(pot);
        Vat = VatLike(vat);

        EDai = WrappedDaiLike(eDai);
        ODai = WrappedDaiLike(oDai);

        require(address(Join.dai()) == dai);
        require(address(Join.vat()) == vat);
        require(address(Pot.vat()) == vat);

        Vat.hope(pot);  // Pot.join
        Vat.hope(join);  // Join.exit

        require(Dai.approve(join, uint(-1)));  // Join.join -> dai.burn
    }

    function setReserve(address reserve) public onlyOwner {
        require(EDai.approve(address(Reserve), 0));
        require(ODai.approve(address(Reserve), 0));

        Reserve = ReserveLike(reserve);

        // approve for Reserve.depositToken
        require(EDai.approve(reserve, uint(-1)));
        require(ODai.approve(reserve, uint(-1)));
    }

    // --- Integration ---
    function grab(uint dai) private returns (uint, uint) {
        // sender의 Dai를 뺏어온다.
        require(Dai.transferFrom(msg.sender, address(this), dai));

        // 가져온 Dai를 소각하고 Vat 생태계로 보낸다.
        Join.join(address(this), dai);

        // Vat에 있는 Dai를 Pot에 넣는다.
        // 버림이 발생하므로 Vat에 미세한 수량이 남는다.
        uint chi = now > Pot.rho() ? Pot.drip() : Pot.chi();
        uint wad = div(mul(dai, ONE), chi);
        Pot.join(wad);

        return (wad, mul(wad, chi) / ONE);
    }

    function depositEDai(address to, uint dai, address extraToAddr) public notPaused {
        (, uint wai) = grab(dai);
        EDai.mint(address(this), wai);
        Reserve.depositToken(address(EDai), to, wai, extraToAddr);
    }

    function depositODai(address to, uint dai, address extraToAddr) public notPaused {
        (uint wad, ) = grab(dai);
        ODai.mint(address(this), wad);
        Reserve.depositToken(address(ODai), to, wad, extraToAddr);
    }

    function swapFromEDai(address from, address to, uint dai) private {
        // 얼마나 돌려줄까?
        uint chi = now > Pot.rho() ? Pot.drip() : Pot.chi();
        uint wad = div(mul(dai, ONE), chi);  // 내림

        EDai.burn(from, dai);

        Pot.exit(wad);

        uint res = mul(wad, chi) / ONE;
        Join.exit(to, res);
    }

    function swapFromODai(address from, address to, uint wad) private {
        // 얼마나 돌려줄까?
        uint chi = now > Pot.rho() ? Pot.drip() : Pot.chi();

        // EDai가 차지한 수량 : eSupply * ONE / chi
        // ODai가 가져도 되는 수량(oWad) : pie - eSupply * ONE / chi

        // 실제 ODai 수량 : oSupply
        // 유저가 빼려는 wad의 비율 : wad / oSupply
        // 유저가 가져갈 수량 : oWad * wad / oSupply

        uint pie = Pot.pie(address(this));
        uint eSupply = EDai.totalSupply();
        uint oSupply = ODai.totalSupply();

        uint oWad = (pie * chi - eSupply * ONE) / chi;
        uint res = div(mul(oWad, wad), oSupply);

        ODai.burn(from, wad);

        Pot.exit(res);

        uint dai = mul(res, chi) / ONE;
        Join.exit(to, dai);
    }

    function withdrawEDai(address to, uint dai) public notPaused {
        swapFromEDai(address(Reserve), to, dai);
    }

    function withdrawODai(address to, uint wad) public notPaused {
        swapFromODai(address(Reserve), to, wad);
    }

    function swapToEDai(uint dai) public notPaused {  // swap해서 다른 유저에게 주려는 시도가 있을까?
        (, uint wai) = grab(dai);
        EDai.mint(msg.sender, wai);
    }

    function swapToODai(uint dai) public notPaused {
        (uint wad, ) = grab(dai);
        ODai.mint(msg.sender, wad);
    }

    function swapFromEDai(uint dai) public notPaused {
        swapFromEDai(msg.sender, msg.sender, dai);
    }

    function swapFromODai(uint wad) public notPaused {
        swapFromODai(msg.sender, msg.sender, wad);
    }

    // --- Migration ---
    DaiProxy public NewProxy;

    modifier onlyNewProxy {
        require(msg.sender == address(NewProxy));
        _;
    }

    function setNewProxy(address proxy) public onlyOwner {
        NewProxy = DaiProxy(proxy);
    }

    function exitPot(address to) public onlyOwner {
        if (now > Pot.rho()) Pot.drip();

        // 지금 있는 것을 다 꺼낸다
        uint pie = Pot.pie(address(this));
        Pot.exit(pie);  // Pot이 텅 비고 Vat으로 감

        uint vat = Vat.dai(address(this));
        Join.exit(to, vat / ONE);
    }

    function movePot() public onlyNewProxy returns (uint) {
        if (now > Pot.rho()) Pot.drip();

        // 지금 있는 것을 다 꺼낸다
        uint pie = Pot.pie(address(this));
        Pot.exit(pie);  // Pot이 텅 비고 Vat으로 감

        uint vat = Vat.dai(address(this));
        Vat.move(address(this), address(NewProxy), vat);

        return pie;  // 이 수량만큼 다시 넣어 주면 됨
    }

    function fillPot(address oldProxy) public onlyOwner {
        if (now > Pot.rho()) Pot.drip();

        uint pie = DaiProxy(oldProxy).movePot();
        Pot.join(pie);
    }
}
