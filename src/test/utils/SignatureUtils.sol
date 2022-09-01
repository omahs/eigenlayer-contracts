// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "ds-test/test.sol";

contract SignatureUtils is DSTest{

    //numSigners => array of signatures for 5 datastores
    mapping(uint256=> uint256[]) signatures;


    
    
    //returns aggPK.X0, aggPK.X1, aggPK.Y0, aggPK.Y1
    function getAggregatePublicKey(uint256 numSigners) internal pure returns (uint256 aggPKX0, uint256 aggPKX1, uint256 aggPKY0, uint256 aggPKY1){

        if(numSigners==15){
            aggPKX0 = uint256(20820493588973199354272631301248587752629863429201347184003644368113679196121);
            aggPKX1 = uint256(18507428821816114421698399069438744284866101909563082454551586195885282320634);
            aggPKY0 = uint256(1263326262781780932600377484793962587101562728383804037421955407439695092960);
            aggPKY1 = uint256(3512517006108887301063578607317108977425754510174956792003926207778790018672);
        }

        if(numSigners==12){
            aggPKX0 = uint256(20523582188987110963974014007824533452740581058607457454770751475798461856790);
            aggPKX1 = uint256(20393417418446180824691701320817867938900127424537147567714032244707813600661);
            aggPKY0 = uint256(4580400133570387826450637471880405528743156066723364760569449578582741304616);
            aggPKY1 = uint256(18368086142287310978311059387137837113783403751688539310101965155145837418588);

        }
        if(numSigners==2){
            aggPKX0 = uint256(13627094809349703367331537758720731786358666292976582438286769018059426535468);
            aggPKX1 = uint256(15990633073361304694314105299377655728793875331567860871472029130760161396005);
            aggPKY0 = uint256(18114822758555812654133893143402128050216537048086929991467442905992867018238);
            aggPKY1 = uint256(15529882236060906134687395001693316326465762665051267458815387894544183627019);


        }

        return (aggPKX0, aggPKX1, aggPKY0, aggPKY1);


    }

    function getSignature(uint256 numSigners, uint index) internal view returns(uint256, uint256){

        return (signatures[numSigners][2*index], signatures[numSigners][2*index+1]);

    }


    function setSignatures() internal{

        //X-coordinate for signature
        signatures[15].push(
            uint256(17495938995352312074042671866638379644300283276197341589218393173802359623203)
        );
        //Y-coordinate for signature
        signatures[15].push(
            uint256(9126369385140686627953696969589239917670210184443620227590862230088267251657)
        );

        //X-coordinate for signature
        signatures[15].push(
            uint256(8528577148191764833611657152174462549210362961117123234946268547773819967468)
        );
        //Y-coordinate for signature
        signatures[15].push(
            uint256(12327969281291293902781100249451937778030476843597859113014633987742778388515)
        );
        //X-coordinate for signature
        signatures[15].push(
            uint256(17717264659294506723357044248913560483603638283216958290715934634714856502042)
        );
        //Y-coordinate for signature
        signatures[15].push(
            uint256(16175010538989710606381988436521433111107391792149336131385412257451345649557)
        );

        //X-coordinate for signature
        signatures[15].push(
            uint256(13634672549209768891995273226026110254116368188641023296736353558981756191079)
        );
        //Y-coordinate for signature
        signatures[15].push(
            uint256(1785013485497898832511190470667377540198821342030868981614348293548355133071)
        );

        //X-coordinate for signature
        signatures[15].push(
            uint256(14314878115196120635834581315654915934806820731149597554562572642636028600046)
        );
        //Y-coordinate for signature
        signatures[15].push(
            uint256(11127341031659236634094533494380792345546001913442488974163761094820943932055)
        );



        //X-coordinate for signature
        signatures[12].push(
            uint256(18235843856910455840729300765034729793593490698095352615310947751502162392559)
        );
        //Y-coordinate for signature
        signatures[12].push(
            uint256(4231264054517009472214512429251462451991675432545372007798546821682511207342)
        );


        //X-coordinate for signature
        signatures[2].push(
            uint256(1427200487656208359269509012982821947310446737744990430200334785028116463226)
        );
        //Y-coordinate for signature
        signatures[2].push(
            uint256(3670588594412709275855651853386803075079692337132176075392411041014435960476)
        );



    }
        
}