import 'package:flutter/material.dart';

import 'figure.dart';

// Liikkeiden sivukuva-animaatiot. Kulmat: 0 alas, 90 eteen, 180 ylös, -90 taakse (ks. figure.dart).
// Liikeperheet jakavat saman perusliikkeen; muunnelmat muuttavat vain eroavat kohdat.

const _floor = .92;
const _benchTop = Prop(rect: Rect.fromLTRB(.18, .63, .78, .68));
const _benchLegs = Prop(rect: Rect.fromLTRB(.24, .68, .28, .92));
const _benchLegs2 = Prop(rect: Rect.fromLTRB(.68, .68, .72, .92));
const _seat = Prop(rect: Rect.fromLTRB(.34, .6, .58, .65));
const _seatPost = Prop(rect: Rect.fromLTRB(.44, .65, .48, .92));

// --- Kyykyt --------------------------------------------------------------
// Alku: seisoen. Ala: reisi vaakatasossa, polvet eteen (sääri -30), vartalo kallistuu.
Motion _squat({
  double lean = 40,
  double armS = -35,
  double foreS = 165,
  Implement imp = Implement.barbell,
  List<Prop> props = const [],
}) => Motion(
  anchor: Anchor.feet,
  implement: imp,
  props: props,
  start: Pose(torso: 180, arm: armS, fore: foreS, anchorAt: const Offset(.5, _floor)),
  end: Pose(
    torso: 180 - lean,
    thigh: 85,
    shin: -32,
    arm: armS - lean * .3,
    fore: foreS - lean,
    anchorAt: const Offset(.5, _floor),
  ),
);

final _backSquat = _squat();
final _lowBar = _squat(lean: 48, armS: -50);
final _frontSquat = _squat(lean: 22, armS: 100, foreS: -95);
final _goblet = _squat(lean: 20, armS: 30, foreS: 175, imp: Implement.dumbbell);
final _boxSquat = _squat(lean: 42, props: const [Prop(rect: Rect.fromLTRB(.2, .68, .42, .92))]);

// --- Maastavedot ja lonkkasarana -----------------------------------------
Motion _deadlift({double thigh = 70, double shin = -22, double torso = 120, Implement imp = Implement.barbell}) =>
    Motion(
      anchor: Anchor.feet,
      implement: imp,
      seconds: 2.8,
      start: Pose(torso: torso, thigh: thigh, shin: shin, arm: 0, fore: 0, anchorAt: const Offset(.5, _floor)),
      end: const Pose(torso: 180, arm: 0, fore: 0, anchorAt: Offset(.5, _floor)),
    );

final _conventional = _deadlift();
final _sumo = _deadlift(thigh: 55, shin: -10, torso: 125);
final _rackPull = _deadlift(thigh: 25, shin: -8, torso: 135);
// RDL: polvet lähes suorina, lantio taakse, selkä suorana; tanko reisiä pitkin.
final _rdl = Motion(
  anchor: Anchor.feet,
  implement: Implement.barbell,
  seconds: 2.8,
  start: const Pose(torso: 180, thigh: 5, shin: -5, anchorAt: Offset(.5, _floor)),
  end: const Pose(torso: 105, thigh: 22, shin: -12, anchorAt: Offset(.5, _floor)),
);
final _stiffLeg = Motion(
  anchor: Anchor.feet,
  implement: Implement.barbell,
  seconds: 2.8,
  start: const Pose(torso: 180, anchorAt: Offset(.5, _floor)),
  end: const Pose(torso: 90, thigh: 22, shin: 0, anchorAt: Offset(.5, _floor)),
);
final _goodMorning = Motion(
  anchor: Anchor.feet,
  implement: Implement.barbell,
  seconds: 2.8,
  start: const Pose(torso: 180, thigh: 5, shin: -5, arm: -35, fore: 165, anchorAt: Offset(.5, _floor)),
  end: const Pose(torso: 100, thigh: 25, shin: -10, arm: -115, fore: 85, anchorAt: Offset(.5, _floor)),
);

// --- Penkki ja työnnöt -----------------------------------------------------
// Selinmakuu, pää vasemmalla: vartalo -90. Ylhäällä kädet suoraan ylös (180), alhaalla kyynärpää
// vartalon alapuolella (olkavarsi ~20) ja kyynärvarsi pystyssä.
Motion _benchPress({
  double torso = -90,
  Implement imp = Implement.barbell,
  double depth = 22,
  bool floor = false,
  double incline = 0,
}) {
  final hip = floor ? const Offset(.62, .885) : const Offset(.62, .6);
  return Motion(
    anchor: Anchor.hip,
    implement: imp,
    props: floor
        ? const []
        : [Prop(rect: const Rect.fromLTRB(.18, .63, .78, .68), rotate: incline), _benchLegs, _benchLegs2],
    start: Pose(torso: torso, thigh: 75, shin: 5, arm: 180 + (torso + 90) * .4, fore: 180, anchorAt: hip),
    end: Pose(torso: torso, thigh: 75, shin: 5, arm: depth + (torso + 90) * .5, fore: 180, anchorAt: hip),
  );
}

final _bench = _benchPress();
final _closeGrip = _benchPress(depth: 10);
final _floorPress = _benchPress(floor: true, depth: 60);
final _dbBench = _benchPress(imp: Implement.dumbbell, depth: 15);
final _incline = _benchPress(torso: -125, incline: 25);
final _dbIncline = _benchPress(torso: -125, incline: 25, imp: Implement.dumbbell);

// Pystypunnerrus: tanko solisluilta suoraan ylös pään yli.
Motion _ohp({Implement imp = Implement.barbell, bool seated = false}) => Motion(
  anchor: seated ? Anchor.hip : Anchor.feet,
  implement: imp,
  props: seated ? const [_seat, _seatPost] : const [],
  start: Pose(
    torso: 180,
    thigh: seated ? 90 : 0,
    shin: 0,
    arm: 35,
    fore: 170,
    anchorAt: seated ? const Offset(.45, .58) : const Offset(.5, _floor),
  ),
  end: Pose(
    torso: 180,
    thigh: seated ? 90 : 0,
    shin: 0,
    arm: 178,
    fore: 180,
    anchorAt: seated ? const Offset(.45, .58) : const Offset(.5, _floor),
  ),
);

final _press = _ohp();
final _dbPress = _ohp(imp: Implement.dumbbell, seated: true);
final _machinePress = _ohp(imp: Implement.machine, seated: true);
final _pushPress = Motion(
  anchor: Anchor.feet,
  implement: Implement.barbell,
  seconds: 1.8,
  start: const Pose(torso: 180, thigh: 20, shin: -18, arm: 35, fore: 170, anchorAt: Offset(.5, _floor)),
  end: const Pose(torso: 180, arm: 178, fore: 180, anchorAt: Offset(.5, _floor)),
);

final _dips = Motion(
  anchor: Anchor.hands,
  props: const [Prop(barFrom: Offset(.42, .47), barTo: Offset(.68, .47))],
  start: const Pose(torso: 175, thigh: 10, shin: -60, arm: 5, fore: 0, anchorAt: Offset(.55, .47)),
  end: const Pose(torso: 160, thigh: 20, shin: -50, arm: -70, fore: 10, anchorAt: Offset(.55, .47)),
);
final _benchDips = Motion(
  anchor: Anchor.hands,
  props: const [
    Prop(rect: Rect.fromLTRB(.12, .6, .4, .65)),
    Prop(rect: Rect.fromLTRB(.2, .65, .24, .92)),
  ],
  start: const Pose(torso: 180, thigh: 85, shin: 82, arm: -15, fore: -8, anchorAt: Offset(.36, .6)),
  end: const Pose(torso: 175, thigh: 70, shin: 105, arm: -75, fore: 8, anchorAt: Offset(.36, .6)),
);
final _pushUp = Motion(
  anchor: Anchor.hands,
  start: const Pose(torso: 108, thigh: -72, shin: -72, arm: 0, fore: 0, anchorAt: Offset(.8, _floor)),
  end: const Pose(torso: 96, thigh: -84, shin: -84, arm: -62, fore: 12, anchorAt: Offset(.8, _floor)),
);

// --- Vedot ---------------------------------------------------------------
// Kulmasoutu: vartalo ~45° kumarassa, tanko vatsaan, kyynärpäät taakse.
Motion _bentRow({Implement imp = Implement.barbell, double torso = 115}) => Motion(
  anchor: Anchor.feet,
  implement: imp,
  start: Pose(torso: torso, thigh: 25, shin: -15, arm: 0, fore: 0, anchorAt: const Offset(.5, _floor)),
  end: Pose(torso: torso, thigh: 25, shin: -15, arm: -60, fore: 5, anchorAt: const Offset(.5, _floor)),
);

final _barbellRow = _bentRow();
final _pendlay = _bentRow(torso: 100);
final _dbRow = _bentRow(imp: Implement.dumbbell, torso: 105);
final _seatedRow = Motion(
  anchor: Anchor.hip,
  implement: Implement.cable,
  cableFrom: const Offset(.92, .7),
  props: const [Prop(rect: Rect.fromLTRB(.25, .74, .55, .79))],
  start: const Pose(torso: 165, thigh: 85, shin: 60, arm: 85, fore: 88, anchorAt: Offset(.38, .73)),
  end: const Pose(torso: 180, thigh: 85, shin: 60, arm: -25, fore: 85, anchorAt: Offset(.38, .73)),
);
final _pullUp = Motion(
  anchor: Anchor.hands,
  seconds: 2.6,
  scale: .68,
  props: const [Prop(barFrom: Offset(.3, .02), barTo: Offset(.7, .02))],
  start: const Pose(torso: 180, thigh: 10, shin: -75, arm: 178, fore: 180, anchorAt: Offset(.52, .02)),
  end: const Pose(torso: 172, thigh: 20, shin: -70, arm: 22, fore: 168, anchorAt: Offset(.52, .02)),
);
final _latPulldown = Motion(
  anchor: Anchor.hip,
  implement: Implement.cable,
  cableFrom: const Offset(.55, .03),
  props: const [_seat, _seatPost],
  start: const Pose(torso: 172, thigh: 90, shin: 0, arm: 175, fore: 178, anchorAt: Offset(.45, .58)),
  end: const Pose(torso: 168, thigh: 90, shin: 0, arm: 20, fore: 165, anchorAt: Offset(.45, .58)),
);
final _straightArm = Motion(
  anchor: Anchor.feet,
  implement: Implement.cable,
  cableFrom: const Offset(.82, .08),
  start: const Pose(torso: 160, thigh: 15, shin: -10, arm: 150, fore: 150, anchorAt: Offset(.45, _floor)),
  end: const Pose(torso: 160, thigh: 15, shin: -10, arm: 10, fore: 10, anchorAt: Offset(.45, _floor)),
);
final _hyperext = Motion(
  anchor: Anchor.hip,
  props: const [Prop(rect: Rect.fromLTRB(.34, .5, .62, .55), rotate: 45)],
  start: const Pose(torso: 130, thigh: -50, shin: -50, arm: 60, fore: 150, anchorAt: Offset(.5, .5)),
  end: const Pose(torso: 45, thigh: -50, shin: -50, arm: -20, fore: 70, anchorAt: Offset(.5, .5)),
);

// --- Kädet ---------------------------------------------------------------
Motion _curl({Implement imp = Implement.barbell, double armFwd = 0}) => Motion(
  anchor: Anchor.feet,
  implement: imp,
  seconds: 2.2,
  start: Pose(torso: 180, arm: armFwd, fore: armFwd, anchorAt: const Offset(.5, _floor)),
  end: Pose(torso: 180, arm: armFwd + 5, fore: 155, anchorAt: const Offset(.5, _floor)),
);

final _bbCurl = _curl();
final _dbCurl = _curl(imp: Implement.dumbbell);
final _cableCurl = Motion(
  anchor: Anchor.feet,
  implement: Implement.cable,
  cableFrom: const Offset(.78, .9),
  start: const Pose(torso: 180, arm: 5, fore: 10, anchorAt: Offset(.45, _floor)),
  end: const Pose(torso: 180, arm: 10, fore: 155, anchorAt: Offset(.45, _floor)),
);
final _preacher = Motion(
  anchor: Anchor.hip,
  implement: Implement.barbell,
  props: const [
    _seat,
    _seatPost,
    Prop(rect: Rect.fromLTRB(.5, .32, .62, .5), rotate: 35),
  ],
  start: const Pose(torso: 165, thigh: 90, shin: 0, arm: 40, fore: 60, anchorAt: Offset(.45, .58)),
  end: const Pose(torso: 165, thigh: 90, shin: 0, arm: 40, fore: 170, anchorAt: Offset(.45, .58)),
);
final _pushdown = Motion(
  anchor: Anchor.feet,
  implement: Implement.cable,
  cableFrom: const Offset(.66, .04),
  start: const Pose(torso: 172, thigh: 8, shin: -8, arm: 8, fore: 120, anchorAt: Offset(.45, _floor)),
  end: const Pose(torso: 172, thigh: 8, shin: -8, arm: 5, fore: 5, anchorAt: Offset(.45, _floor)),
);
final _skullcrusher = Motion(
  anchor: Anchor.hip,
  implement: Implement.barbell,
  props: const [_benchTop, _benchLegs, _benchLegs2],
  start: const Pose(torso: -90, thigh: 75, shin: 5, arm: 165, fore: 165, anchorAt: Offset(.62, .6)),
  end: const Pose(torso: -90, thigh: 75, shin: 5, arm: 165, fore: 40, anchorAt: Offset(.62, .6)),
);
final _overheadExt = Motion(
  anchor: Anchor.feet,
  implement: Implement.dumbbell,
  start: const Pose(torso: 180, arm: 175, fore: 178, anchorAt: Offset(.5, _floor)),
  end: const Pose(torso: 180, arm: 175, fore: 25, anchorAt: Offset(.5, _floor)),
);

// --- Jalat ---------------------------------------------------------------
final _legPress = Motion(
  anchor: Anchor.hip,
  props: const [
    Prop(rect: Rect.fromLTRB(.12, .55, .42, .6), rotate: -35),
    Prop(rect: Rect.fromLTRB(.68, .2, .74, .42), rotate: 45),
  ],
  start: const Pose(torso: -125, thigh: 150, shin: 95, arm: -100, fore: -60, anchorAt: Offset(.36, .7)),
  end: const Pose(torso: -125, thigh: 125, shin: 125, arm: -100, fore: -60, anchorAt: Offset(.36, .7)),
);
final _legExt = Motion(
  anchor: Anchor.hip,
  implement: Implement.machine,
  props: const [_seat, _seatPost],
  start: const Pose(torso: 170, thigh: 90, shin: 5, arm: 10, fore: 60, anchorAt: Offset(.45, .58)),
  end: const Pose(torso: 170, thigh: 90, shin: 88, arm: 10, fore: 60, anchorAt: Offset(.45, .58)),
);
final _legCurl = Motion(
  anchor: Anchor.hip,
  implement: Implement.machine,
  props: const [_seat, _seatPost],
  start: const Pose(torso: 165, thigh: 90, shin: 75, arm: 10, fore: 60, anchorAt: Offset(.45, .58)),
  end: const Pose(torso: 165, thigh: 90, shin: -20, arm: 10, fore: 60, anchorAt: Offset(.45, .58)),
);
final _calfStanding = Motion(
  anchor: Anchor.feet,
  scale: .75,
  implement: Implement.machine,
  seconds: 1.6,
  props: const [Prop(rect: Rect.fromLTRB(.44, .9, .62, .93))],
  start: const Pose(torso: 180, arm: -30, fore: 165, anchorAt: Offset(.5, .9)),
  end: const Pose(torso: 180, arm: -30, fore: 165, anchorAt: Offset(.5, .84)),
);
final _calfSeated = Motion(
  anchor: Anchor.hip,
  implement: Implement.machine,
  seconds: 1.6,
  props: const [_seat, _seatPost],
  start: const Pose(torso: 175, thigh: 90, shin: 0, arm: 30, fore: 100, anchorAt: Offset(.45, .58)),
  end: const Pose(torso: 175, thigh: 88, shin: -4, arm: 30, fore: 100, anchorAt: Offset(.45, .53)),
);
// Hip thrust: lavat penkillä, lantio ylös vaakatasoon.
final _hipThrust = Motion(
  anchor: Anchor.feet,
  implement: Implement.barbell,
  props: const [
    Prop(rect: Rect.fromLTRB(.06, .7, .3, .76)),
    Prop(rect: Rect.fromLTRB(.15, .76, .19, .92)),
  ],
  start: const Pose(torso: -115, thigh: 125, shin: -5, arm: 30, fore: 90, anchorAt: Offset(.66, _floor)),
  end: const Pose(torso: -88, thigh: 92, shin: 0, arm: 30, fore: 90, anchorAt: Offset(.66, _floor)),
);
// Askelkyykky: etujalan reisi vaakaan, takapolvi kohti lattiaa.
Motion _lunge({Implement imp = Implement.dumbbell, bool rearOnBench = false}) => Motion(
  anchor: Anchor.feet,
  implement: imp,
  props: rearOnBench
      ? const [Prop(rect: Rect.fromLTRB(.06, .66, .26, .72)), Prop(rect: Rect.fromLTRB(.14, .72, .18, .92))]
      : const [],
  start: Pose(
    torso: 180,
    thigh: 15,
    shin: -5,
    thigh2: rearOnBench ? -30 : -25,
    shin2: rearOnBench ? -100 : -10,
    anchorAt: const Offset(.62, _floor),
  ),
  end: Pose(
    torso: 175,
    thigh: 88,
    shin: -8,
    thigh2: rearOnBench ? -15 : -5,
    shin2: rearOnBench ? -80 : -95,
    anchorAt: const Offset(.62, _floor),
  ),
);

final _lungeDb = _lunge();
final _bulgarian = _lunge(rearOnBench: true);
final _walk = Motion(
  anchor: Anchor.hip,
  implement: Implement.dumbbell,
  seconds: 0.9,
  start: const Pose(torso: 180, thigh: 22, shin: -5, thigh2: -18, shin2: -30, anchorAt: Offset(.5, .44)),
  end: const Pose(torso: 180, thigh: -18, shin: -30, thigh2: 22, shin2: -5, anchorAt: Offset(.5, .44)),
);

// --- Keskivartalo ----------------------------------------------------------
final _plank = Motion(
  anchor: Anchor.feet,
  seconds: 3,
  start: const Pose(torso: 101, thigh: -79, shin: -79, arm: 0, fore: 90, anchorAt: Offset(.08, _floor)),
  end: const Pose(torso: 102, thigh: -78, shin: -78, arm: 0, fore: 90, anchorAt: Offset(.08, _floor)),
);
final _crunch = Motion(
  anchor: Anchor.hip,
  start: const Pose(torso: -95, thigh: 140, shin: 30, arm: -60, fore: 120, anchorAt: Offset(.5, .87)),
  end: const Pose(torso: -128, thigh: 140, shin: 30, arm: -25, fore: 155, anchorAt: Offset(.5, .87)),
);
final _hangingRaise = Motion(
  anchor: Anchor.hands,
  scale: .5,
  props: const [Prop(barFrom: Offset(.3, -.05), barTo: Offset(.7, -.05))],
  start: const Pose(torso: 180, thigh: 5, shin: 0, arm: 178, fore: 180, anchorAt: Offset(.5, -.05)),
  end: const Pose(torso: 172, thigh: 95, shin: 88, arm: 178, fore: 180, anchorAt: Offset(.5, -.05)),
);

// --- Kahvakuula -------------------------------------------------------------
// Heilautus: lonkkasarana, kuula jalkojen välistä rinnan korkeudelle; kädet ovat vain koukut.
const _kbBottom = Pose(torso: 118, thigh: 28, shin: -12, arm: -25, fore: -30, anchorAt: Offset(.5, _floor));
const _kbRack = Pose(torso: 180, arm: 15, fore: 165, anchorAt: Offset(.5, _floor));
const _kbOverhead = Pose(torso: 180, arm: 178, fore: 180, anchorAt: Offset(.5, _floor));
final _kbSwing = Motion(
  anchor: Anchor.feet,
  implement: Implement.kettlebell,
  seconds: 1.1,
  start: _kbBottom,
  end: const Pose(torso: 180, arm: 90, fore: 90, anchorAt: Offset(.5, _floor)),
);
final _kbDeadlift = Motion(
  anchor: Anchor.feet,
  implement: Implement.kettlebell,
  seconds: 2.4,
  start: const Pose(torso: 125, thigh: 60, shin: -18, arm: 0, fore: 0, anchorAt: Offset(.5, _floor)),
  end: const Pose(torso: 180, arm: 0, fore: 0, anchorAt: Offset(.5, _floor)),
);
final _kbClean = Motion(
  anchor: Anchor.feet,
  implement: Implement.kettlebell,
  seconds: 1.3,
  start: _kbBottom,
  end: _kbRack,
);
final _kbSnatch = Motion(
  anchor: Anchor.feet,
  implement: Implement.kettlebell,
  seconds: 1.4,
  start: _kbBottom,
  end: _kbOverhead,
);
final _kbPress = Motion(anchor: Anchor.feet, implement: Implement.kettlebell, start: _kbRack, end: _kbOverhead);
final _kbFrontSquat = _squat(lean: 18, armS: 15, foreS: 165, imp: Implement.kettlebell);
final _kbThruster = Motion(
  anchor: Anchor.feet,
  implement: Implement.kettlebell,
  seconds: 2,
  start: const Pose(torso: 162, thigh: 85, shin: -32, arm: 10, fore: 150, anchorAt: Offset(.5, _floor)),
  end: _kbOverhead,
);
final _kbSingleLegRdl = Motion(
  anchor: Anchor.feet,
  implement: Implement.kettlebell,
  seconds: 2.6,
  start: const Pose(torso: 180, thigh: 3, shin: -3, thigh2: -5, shin2: -15, anchorAt: Offset(.55, _floor)),
  end: const Pose(torso: 95, thigh: 18, shin: -8, thigh2: -92, shin2: -92, anchorAt: Offset(.55, _floor)),
);
final _kbRow = _bentRow(imp: Implement.kettlebell, torso: 105);
final _kbFloorPress = _benchPress(floor: true, depth: 60, imp: Implement.kettlebell);
final _suitcase = Motion(
  anchor: Anchor.hip,
  implement: Implement.kettlebell,
  seconds: 0.9,
  start: const Pose(torso: 180, thigh: 22, shin: -5, thigh2: -18, shin2: -30, anchorAt: Offset(.5, .44)),
  end: const Pose(torso: 180, thigh: -18, shin: -30, thigh2: 22, shin2: -5, anchorAt: Offset(.5, .44)),
);
// Lantionnosto lattialla: lavat lattiassa, lantio ylös.
final _glueBridge = Motion(
  anchor: Anchor.feet,
  start: const Pose(torso: -78, thigh: 125, shin: -15, arm: -95, fore: -95, anchorAt: Offset(.66, _floor)),
  end: const Pose(torso: -50, thigh: 95, shin: -5, arm: -105, fore: -105, anchorAt: Offset(.66, _floor)),
);
// Pistoolikyykky: tukijalka koukistuu, toinen jalka suorana eteen.
final _pistol = Motion(
  anchor: Anchor.feet,
  seconds: 2.6,
  start: const Pose(torso: 180, arm: 90, fore: 90, thigh2: 30, shin2: 30, anchorAt: Offset(.45, _floor)),
  end: const Pose(
    torso: 140,
    thigh: 95,
    shin: -35,
    arm: 95,
    fore: 95,
    thigh2: 92,
    shin2: 92,
    anchorAt: Offset(.45, _floor),
  ),
);

// --- Kehonpaino ----------------------------------------------------------------
final _airSquat = _squat(lean: 30, armS: 85, foreS: 85, imp: Implement.none);
final _jumpSquat = Motion(
  anchor: Anchor.feet,
  seconds: 1.2,
  scale: .68,
  start: const Pose(torso: 145, thigh: 85, shin: -32, arm: -45, fore: -45, anchorAt: Offset(.5, _floor)),
  end: const Pose(torso: 180, thigh: 2, shin: -8, arm: 160, fore: 165, anchorAt: Offset(.5, _floor - .06)),
);
final _sissy = Motion(
  anchor: Anchor.feet,
  seconds: 2.6,
  props: const [Prop(barFrom: Offset(.78, .45), barTo: Offset(.78, _floor))],
  start: const Pose(torso: 180, thigh: 0, shin: 0, arm: 90, fore: 90, anchorAt: Offset(.45, _floor)),
  end: const Pose(torso: 200, thigh: 75, shin: -55, arm: 80, fore: 80, anchorAt: Offset(.45, _floor)),
);
final _reverseNordic = Motion(
  anchor: Anchor.feet,
  seconds: 2.8,
  start: const Pose(torso: 180, thigh: 0, shin: -90, arm: 90, fore: 90, anchorAt: Offset(.3, _floor - .01)),
  end: const Pose(torso: 212, thigh: 32, shin: -90, arm: 120, fore: 120, anchorAt: Offset(.3, _floor - .01)),
);
final _declinePushUp = Motion(
  anchor: Anchor.hands,
  props: const [
    Prop(rect: Rect.fromLTRB(.02, .66, .3, .72)),
    Prop(rect: Rect.fromLTRB(.12, .72, .16, .92)),
  ],
  start: const Pose(torso: 98, thigh: -96, shin: -96, arm: 0, fore: 0, anchorAt: Offset(.82, _floor)),
  end: const Pose(torso: 84, thigh: -98, shin: -98, arm: -62, fore: 12, anchorAt: Offset(.82, _floor)),
);
final _pikePushUp = Motion(
  anchor: Anchor.hands,
  start: const Pose(torso: 40, thigh: -38, shin: -38, arm: 8, fore: 8, anchorAt: Offset(.66, _floor)),
  end: const Pose(torso: 58, thigh: -30, shin: -30, arm: -45, fore: 25, anchorAt: Offset(.66, _floor)),
);
final _hspu = Motion(
  anchor: Anchor.hands,
  scale: .62,
  props: const [Prop(rect: Rect.fromLTRB(.6, -.3, .64, _floor))],
  start: const Pose(torso: 2, thigh: 178, shin: 178, arm: 2, fore: 2, anchorAt: Offset(.5, _floor)),
  end: const Pose(torso: 4, thigh: 176, shin: 176, arm: 60, fore: -60, anchorAt: Offset(.5, _floor)),
);
final _singleLegBridge = Motion(
  anchor: Anchor.feet,
  start: const Pose(
    torso: -78,
    thigh: 125,
    shin: -15,
    thigh2: 140,
    shin2: 140,
    arm: -95,
    fore: -95,
    anchorAt: Offset(.66, _floor),
  ),
  end: const Pose(
    torso: -50,
    thigh: 95,
    shin: -5,
    thigh2: 112,
    shin2: 112,
    arm: -105,
    fore: -105,
    anchorAt: Offset(.66, _floor),
  ),
);
final _bwLegCurl = Motion(
  anchor: Anchor.feet,
  start: const Pose(torso: -82, thigh: 85, shin: 85, arm: -100, fore: -100, anchorAt: Offset(.86, _floor)),
  end: const Pose(torso: -52, thigh: 105, shin: -10, arm: -100, fore: -100, anchorAt: Offset(.62, _floor)),
);
final _hollow = Motion(
  anchor: Anchor.hip,
  seconds: 3,
  start: const Pose(torso: -108, thigh: 102, shin: 102, arm: -118, fore: -118, anchorAt: Offset(.5, _floor - .02)),
  end: const Pose(torso: -110, thigh: 104, shin: 104, arm: -120, fore: -120, anchorAt: Offset(.5, _floor - .02)),
);
final _deadBug = Motion(
  anchor: Anchor.hip,
  start: const Pose(torso: -90, thigh: 180, shin: 90, arm: 180, fore: 180, anchorAt: Offset(.55, _floor - .02)),
  end: const Pose(
    torso: -90,
    thigh: 98,
    shin: 98,
    thigh2: 180,
    shin2: 90,
    arm: -100,
    fore: -100,
    arm2: 180,
    fore2: 180,
    anchorAt: Offset(.55, _floor - .02),
  ),
);
final _ytw = Motion(
  anchor: Anchor.hip,
  start: const Pose(torso: 92, thigh: -88, shin: -88, arm: -92, fore: -92, anchorAt: Offset(.42, _floor - .03)),
  end: const Pose(torso: 94, thigh: -88, shin: -88, arm: 105, fore: 105, anchorAt: Offset(.42, _floor - .03)),
);
final _superman = Motion(
  anchor: Anchor.hip,
  start: const Pose(torso: 90, thigh: -90, shin: -90, arm: 92, fore: 92, anchorAt: Offset(.45, _floor - .03)),
  end: const Pose(torso: 102, thigh: -100, shin: -100, arm: 108, fore: 108, anchorAt: Offset(.45, _floor - .03)),
);
final _stepUp = Motion(
  anchor: Anchor.feet,
  props: const [Prop(rect: Rect.fromLTRB(.5, .74, .78, _floor))],
  start: const Pose(
    torso: 170,
    thigh: 80,
    shin: -12,
    thigh2: -15,
    shin2: -10,
    arm: 20,
    fore: 20,
    anchorAt: Offset(.62, .74),
  ),
  end: const Pose(
    torso: 180,
    thigh: 0,
    shin: 0,
    thigh2: 35,
    shin2: -60,
    arm: -10,
    fore: -10,
    anchorAt: Offset(.62, .74),
  ),
);

// --- Kehonpaino: aloittelijan etenemiset -------------------------------------
final _inclinePushUp = Motion(
  anchor: Anchor.hands,
  props: const [
    Prop(rect: Rect.fromLTRB(.66, .63, .92, .68)),
    Prop(rect: Rect.fromLTRB(.86, .68, .9, .92)),
  ],
  start: const Pose(torso: 122, thigh: -58, shin: -58, arm: 0, fore: 0, anchorAt: Offset(.78, .63)),
  end: const Pose(torso: 112, thigh: -66, shin: -66, arm: -62, fore: 12, anchorAt: Offset(.78, .63)),
);
final _kneePushUp = Motion(
  anchor: Anchor.hands,
  start: const Pose(torso: 112, thigh: -70, shin: -100, arm: 0, fore: 0, anchorAt: Offset(.74, _floor)),
  end: const Pose(torso: 98, thigh: -83, shin: -96, arm: -62, fore: 12, anchorAt: Offset(.74, _floor)),
);
final _negativePullUp = Motion(
  anchor: Anchor.hands,
  seconds: 3.5,
  scale: .68,
  props: const [Prop(barFrom: Offset(.3, .02), barTo: Offset(.7, .02))],
  start: const Pose(torso: 172, thigh: 20, shin: -70, arm: 22, fore: 168, anchorAt: Offset(.52, .02)),
  end: const Pose(torso: 180, thigh: 10, shin: -75, arm: 178, fore: 180, anchorAt: Offset(.52, .02)),
);
final _deadHang = Motion(
  anchor: Anchor.hands,
  seconds: 3,
  scale: .68,
  props: const [Prop(barFrom: Offset(.3, .02), barTo: Offset(.7, .02))],
  start: const Pose(torso: 180, thigh: 8, shin: -75, arm: 178, fore: 180, anchorAt: Offset(.52, .02)),
  end: const Pose(torso: 180, thigh: 10, shin: -76, arm: 179, fore: 180, anchorAt: Offset(.52, .02)),
);
final _scapPull = Motion(
  anchor: Anchor.hands,
  seconds: 1.6,
  scale: .68,
  props: const [Prop(barFrom: Offset(.3, .02), barTo: Offset(.7, .02))],
  start: const Pose(torso: 180, thigh: 8, shin: -75, arm: 178, fore: 180, anchorAt: Offset(.52, .02)),
  end: const Pose(torso: 175, thigh: 12, shin: -72, arm: 160, fore: 186, anchorAt: Offset(.52, .02)),
);
final _wallSit = Motion(
  anchor: Anchor.feet,
  seconds: 3,
  props: const [Prop(rect: Rect.fromLTRB(.16, .2, .2, _floor))],
  start: const Pose(torso: 180, thigh: 90, shin: 0, arm: 0, fore: 0, anchorAt: Offset(.46, _floor)),
  end: const Pose(torso: 180, thigh: 91, shin: 0, arm: 0, fore: 0, anchorAt: Offset(.46, _floor)),
);
final _birdDog = Motion(
  anchor: Anchor.hip,
  seconds: 2.6,
  start: const Pose(torso: 90, thigh: 0, shin: -90, arm: 0, fore: 0, anchorAt: Offset(.4, _floor - .24)),
  end: const Pose(
    torso: 90,
    thigh: 0,
    shin: -90,
    thigh2: -88,
    shin2: -88,
    arm: 92,
    fore: 92,
    arm2: 0,
    fore2: 0,
    anchorAt: Offset(.4, _floor - .24),
  ),
);
final _mountainClimber = Motion(
  anchor: Anchor.hands,
  seconds: .8,
  start: const Pose(
    torso: 106,
    thigh: -74,
    shin: -74,
    thigh2: -74,
    shin2: -74,
    arm: 0,
    fore: 0,
    anchorAt: Offset(.8, _floor),
  ),
  end: const Pose(
    torso: 108,
    thigh: 60,
    shin: -80,
    thigh2: -74,
    shin2: -74,
    arm: 0,
    fore: 0,
    anchorAt: Offset(.8, _floor),
  ),
);
final _bearCrawl = Motion(
  anchor: Anchor.hip,
  seconds: 1,
  start: const Pose(
    torso: 92,
    thigh: 18,
    shin: -78,
    thigh2: -8,
    shin2: -78,
    arm: 25,
    fore: 25,
    arm2: -5,
    fore2: -5,
    anchorAt: Offset(.42, _floor - .28),
  ),
  end: const Pose(
    torso: 92,
    thigh: -8,
    shin: -78,
    thigh2: 18,
    shin2: -78,
    arm: -5,
    fore: -5,
    arm2: 25,
    fore2: 25,
    anchorAt: Offset(.46, _floor - .28),
  ),
);

/// Liike -> animaatio. Liikkeet, joita sivukuva ei näytä hyvin (esim. vipunosto sivulle,
/// lonkan loitonnus), puuttuvat; niille näytetään vain tekniikkavinkit.

// --- Loput liikkeet (2026-11-07): sivukuvassa näkyvä pääliike; sivuttaiset liikkeet likimääräisinä ---
final _hipAbduction = Motion(
  anchor: Anchor.hip,
  implement: Implement.machine,
  props: const [_seat, _seatPost],
  start: const Pose(torso: 170, thigh: 90, shin: 0, arm: 40, fore: 80, anchorAt: Offset(.45, .58)),
  end: const Pose(torso: 170, thigh: 78, shin: -8, arm: 40, fore: 80, anchorAt: Offset(.45, .58)),
);
final _hipAdduction = Motion(
  anchor: Anchor.hip,
  implement: Implement.machine,
  props: const [_seat, _seatPost],
  start: const Pose(torso: 170, thigh: 78, shin: -8, arm: 40, fore: 80, anchorAt: Offset(.45, .58)),
  end: const Pose(torso: 170, thigh: 90, shin: 0, arm: 40, fore: 80, anchorAt: Offset(.45, .58)),
);
// Nordic: polvet maassa, nilkat kiinni; vartalo laskee suorana eteen polvista.
final _nordic = Motion(
  anchor: Anchor.feet,
  seconds: 3,
  start: const Pose(torso: 180, thigh: 0, shin: -90, arm: 0, fore: 0, anchorAt: Offset(.3, _floor)),
  end: const Pose(torso: 138, thigh: -42, shin: -90, arm: 100, fore: 100, anchorAt: Offset(.3, _floor)),
);
final _sidePlank = Motion(
  anchor: Anchor.feet,
  seconds: 3,
  start: const Pose(torso: 98, thigh: -82, shin: -82, arm: 0, fore: 90, anchorAt: Offset(.1, _floor)),
  end: const Pose(torso: 100, thigh: -80, shin: -80, arm: 0, fore: 90, anchorAt: Offset(.1, _floor)),
);
// Kööpenhamina: kylkilankku, ylempi jalka penkillä; lantio nousee.
final _copenhagen = Motion(
  anchor: Anchor.feet,
  props: const [
    Prop(rect: Rect.fromLTRB(.02, .72, .22, .77)),
    Prop(rect: Rect.fromLTRB(.1, .77, .14, .92)),
  ],
  start: const Pose(torso: 78, thigh: -95, shin: -95, arm: 0, fore: 90, anchorAt: Offset(.12, .72)),
  end: const Pose(torso: 88, thigh: -88, shin: -88, arm: 0, fore: 90, anchorAt: Offset(.12, .72)),
);
final _cableCross = Motion(
  anchor: Anchor.feet,
  implement: Implement.cable,
  cableFrom: const Offset(.25, .05),
  start: const Pose(torso: 165, thigh: 15, shin: -10, arm: 140, fore: 130, anchorAt: Offset(.45, _floor)),
  end: const Pose(torso: 165, thigh: 15, shin: -10, arm: 70, fore: 85, anchorAt: Offset(.45, _floor)),
);
final _peckDeck = Motion(
  anchor: Anchor.hip,
  implement: Implement.machine,
  props: const [_seat, _seatPost],
  start: const Pose(torso: 178, thigh: 90, shin: 0, arm: 60, fore: 150, anchorAt: Offset(.45, .58)),
  end: const Pose(torso: 178, thigh: 90, shin: 0, arm: 95, fore: 175, anchorAt: Offset(.45, .58)),
);
final _dbFly = Motion(
  anchor: Anchor.hip,
  implement: Implement.dumbbell,
  props: const [_benchTop, _benchLegs, _benchLegs2],
  start: const Pose(torso: -90, thigh: 75, shin: 5, arm: 180, fore: 180, anchorAt: Offset(.62, .6)),
  end: const Pose(torso: -90, thigh: 75, shin: 5, arm: 75, fore: 105, anchorAt: Offset(.62, .6)),
);
final _shrug = Motion(
  anchor: Anchor.feet,
  implement: Implement.dumbbell,
  start: const Pose(torso: 180, arm: 0, fore: 0, anchorAt: Offset(.5, _floor)),
  end: const Pose(torso: 180, arm: 4, fore: 4, anchorAt: Offset(.5, _floor)),
);
// Australialainen leuanveto: vartalo suorana tangon alla, kantapäät lattialla.
final _invertedRow = Motion(
  anchor: Anchor.hands,
  props: const [Prop(barFrom: Offset(.6, .42), barTo: Offset(.9, .42))],
  start: const Pose(torso: 112, thigh: -68, shin: -68, arm: 180, fore: 180, anchorAt: Offset(.75, .42)),
  end: const Pose(torso: 104, thigh: -76, shin: -76, arm: -40, fore: 130, anchorAt: Offset(.75, .42)),
);
Motion _raise({double toArm = 85, Implement imp = Implement.dumbbell, double torso = 180, Offset? cable}) => Motion(
  anchor: Anchor.feet,
  implement: imp,
  cableFrom: cable,
  start: Pose(
    torso: torso,
    thigh: torso < 180 ? 25 : 0,
    shin: torso < 180 ? -15 : 0,
    arm: 0,
    fore: 0,
    anchorAt: const Offset(.5, _floor),
  ),
  end: Pose(
    torso: torso,
    thigh: torso < 180 ? 25 : 0,
    shin: torso < 180 ? -15 : 0,
    arm: toArm,
    fore: toArm + 5,
    anchorAt: const Offset(.5, _floor),
  ),
);
final _lateralRaise = _raise(toArm: 75);
final _frontRaise = _raise(toArm: 92);
final _rearDelt = _raise(toArm: -55, torso: 108);
final _cableLateral = _raise(toArm: 75, imp: Implement.cable, cable: const Offset(.3, .9));
final _uprightRow = Motion(
  anchor: Anchor.feet,
  implement: Implement.barbell,
  start: const Pose(torso: 180, arm: 0, fore: 0, anchorAt: Offset(.5, _floor)),
  end: const Pose(torso: 180, arm: 125, fore: -15, anchorAt: Offset(.5, _floor)),
);
final _facePull = Motion(
  anchor: Anchor.feet,
  implement: Implement.cable,
  cableFrom: const Offset(.95, .3),
  start: const Pose(torso: 175, thigh: 10, shin: -10, arm: 88, fore: 88, anchorAt: Offset(.4, _floor)),
  end: const Pose(torso: 178, thigh: 10, shin: -10, arm: 80, fore: 165, anchorAt: Offset(.4, _floor)),
);
final _externalRotation = Motion(
  anchor: Anchor.feet,
  implement: Implement.cable,
  cableFrom: const Offset(.9, .55),
  start: const Pose(torso: 180, arm: 0, fore: 90, anchorAt: Offset(.45, _floor)),
  end: const Pose(torso: 180, arm: 0, fore: 35, anchorAt: Offset(.45, _floor)),
);
final _concentrationCurl = Motion(
  anchor: Anchor.hip,
  implement: Implement.dumbbell,
  props: const [_seat, _seatPost],
  start: const Pose(torso: 130, thigh: 90, shin: 0, arm: 0, fore: 0, anchorAt: Offset(.4, .58)),
  end: const Pose(torso: 130, thigh: 90, shin: 0, arm: 5, fore: 150, anchorAt: Offset(.4, .58)),
);
Motion _wrist(double a, double b) => Motion(
  anchor: Anchor.hip,
  implement: Implement.dumbbell,
  props: const [_seat, _seatPost],
  start: Pose(torso: 145, thigh: 90, shin: 0, arm: 30, fore: a, anchorAt: const Offset(.4, .58)),
  end: Pose(torso: 145, thigh: 90, shin: 0, arm: 30, fore: b, anchorAt: const Offset(.4, .58)),
);
final _wristCurl = _wrist(85, 105);
final _wristExt = _wrist(105, 85);
// Ab wheel: polviltaan, kädet rullalla; lantio ja kädet liikkuvat eteen.
final _abWheel = Motion(
  anchor: Anchor.feet,
  seconds: 2.8,
  start: const Pose(torso: 125, thigh: -10, shin: -90, arm: 5, fore: 5, anchorAt: Offset(.2, _floor)),
  end: const Pose(torso: 98, thigh: -70, shin: -90, arm: 92, fore: 92, anchorAt: Offset(.2, _floor)),
);
final _pallof = Motion(
  anchor: Anchor.feet,
  implement: Implement.cable,
  cableFrom: const Offset(.15, .5),
  start: const Pose(torso: 180, thigh: 8, shin: -8, arm: 10, fore: 120, anchorAt: Offset(.5, _floor)),
  end: const Pose(torso: 180, thigh: 8, shin: -8, arm: 88, fore: 90, anchorAt: Offset(.5, _floor)),
);
final _russianTwist = Motion(
  anchor: Anchor.hip,
  seconds: 1.6,
  start: const Pose(torso: -135, thigh: 125, shin: 75, arm: 120, fore: 160, anchorAt: Offset(.5, _floor - .02)),
  end: const Pose(torso: -132, thigh: 125, shin: 75, arm: 70, fore: 120, anchorAt: Offset(.5, _floor - .02)),
);
// Kaapelirutistus: polviltaan, köysi pään vieressä; vartalo rullautuu alas.
final _cableCrunch = Motion(
  anchor: Anchor.feet,
  implement: Implement.cable,
  cableFrom: const Offset(.6, .03),
  start: const Pose(torso: 165, thigh: 5, shin: -90, arm: 160, fore: -15, anchorAt: Offset(.3, _floor)),
  end: const Pose(torso: 95, thigh: 20, shin: -90, arm: 60, fore: -10, anchorAt: Offset(.3, _floor)),
);
final _bwTricepsExt = Motion(
  anchor: Anchor.hands,
  props: const [
    Prop(rect: Rect.fromLTRB(.66, .62, .96, .67)),
    Prop(rect: Rect.fromLTRB(.86, .67, .9, .92)),
  ],
  start: const Pose(torso: 118, thigh: -62, shin: -62, arm: -5, fore: -5, anchorAt: Offset(.74, .62)),
  end: const Pose(torso: 112, thigh: -68, shin: -68, arm: 70, fore: -10, anchorAt: Offset(.74, .62)),
);
final _bwCurl = Motion(
  anchor: Anchor.hands,
  props: const [Prop(barFrom: Offset(.6, .42), barTo: Offset(.9, .42))],
  start: const Pose(torso: 112, thigh: -68, shin: -68, arm: 180, fore: 180, anchorAt: Offset(.75, .42)),
  end: const Pose(torso: 106, thigh: -74, shin: -74, arm: 150, fore: 20, anchorAt: Offset(.75, .42)),
);
// Burpee: kyykystä kädet maahan ja jalat taakse lankkuun (ja takaisin).
final _burpee = Motion(
  anchor: Anchor.hands,
  seconds: 1.6,
  start: const Pose(torso: 120, thigh: 75, shin: -40, arm: 0, fore: 0, anchorAt: Offset(.62, _floor)),
  end: const Pose(torso: 108, thigh: -72, shin: -72, arm: 0, fore: 0, anchorAt: Offset(.75, _floor)),
);
final _renegade = Motion(
  anchor: Anchor.hands,
  implement: Implement.kettlebell,
  start: const Pose(
    torso: 108,
    thigh: -72,
    shin: -72,
    arm: 0,
    fore: 0,
    arm2: 0,
    fore2: 0,
    anchorAt: Offset(.75, _floor),
  ),
  end: const Pose(
    torso: 108,
    thigh: -72,
    shin: -72,
    arm: 0,
    fore: 0,
    arm2: -60,
    fore2: 5,
    anchorAt: Offset(.75, _floor),
  ),
);
// Turkkilainen ylösnousu (alkuosa): selinmakuulta kyynärpään kautta istumaan, kuula suoralla kädellä ylhäällä.
final _getUp = Motion(
  anchor: Anchor.hip,
  implement: Implement.kettlebell,
  seconds: 3,
  start: const Pose(
    torso: -90,
    thigh: 90,
    shin: 90,
    thigh2: 50,
    shin2: -40,
    arm: 180,
    fore: 180,
    arm2: -60,
    fore2: -60,
    anchorAt: Offset(.55, _floor - .02),
  ),
  end: const Pose(
    torso: -165,
    thigh: 90,
    shin: 90,
    thigh2: 50,
    shin2: -40,
    arm: 180,
    fore: 180,
    arm2: -10,
    fore2: -10,
    anchorAt: Offset(.55, _floor - .02),
  ),
);
final _windmill = Motion(
  anchor: Anchor.feet,
  implement: Implement.kettlebell,
  seconds: 3,
  start: const Pose(torso: 180, arm: 180, fore: 180, arm2: 0, fore2: 0, anchorAt: Offset(.5, _floor)),
  end: const Pose(
    torso: 112,
    thigh: 10,
    shin: -5,
    arm: 180,
    fore: 180,
    arm2: 0,
    fore2: 0,
    anchorAt: Offset(.5, _floor),
  ),
);

final _kbHighPull = Motion(
  anchor: Anchor.feet,
  implement: Implement.kettlebell,
  start: const Pose(torso: 130, thigh: 50, shin: -20, arm: 0, fore: 0, anchorAt: Offset(.5, _floor)),
  end: const Pose(torso: 180, arm: 120, fore: -10, anchorAt: Offset(.5, _floor)),
);
final _kbCurl = _curl(imp: Implement.kettlebell);
final _kbLunge = _lunge(imp: Implement.kettlebell);

final Map<String, Motion> exerciseMotions = {
  'Takakyykky': _backSquat,
  'Low bar -kyykky': _lowBar,
  'Box-kyykky': _boxSquat,
  'Smith-kyykky': _backSquat,
  'Hack-kyykky': _squat(lean: 15, imp: Implement.machine),
  'Etukyykky': _frontSquat,
  'Goblet-kyykky': _goblet,
  'Maastaveto': _conventional,
  'Sumomaastaveto': _sumo,
  'Rack pull': _rackPull,
  'Romanialainen maastaveto': _rdl,
  'Suorin jaloin maastaveto': _stiffLeg,
  'Good morning': _goodMorning,
  'Penkkipunnerrus': _bench,
  'Taukopenkki': _bench,
  'Kapea penkki': _closeGrip,
  'Lattiapunnerrus': _floorPress,
  'Käsipainopenkki': _dbBench,
  'Rintaprässi laitteessa': _benchPress(imp: Implement.machine),
  'Vinopenkki': _incline,
  'Smith-vinopenkki': _incline,
  'Vinokäsipainopenkki': _dbIncline,
  'Pystypunnerrus': _press,
  'Push press': _pushPress,
  'Käsipainopystypunnerrus': _dbPress,
  'Arnold-punnerrus': _dbPress,
  'Olkapääprässi laitteessa': _machinePress,
  'Dipit': _dips,
  'Penkkidipit': _benchDips,
  'Punnerrus': _pushUp,
  'Kulmasoutu': _barbellRow,
  'Pendlay-soutu': _pendlay,
  'T-tankosoutu': _barbellRow,
  'Käsipainosoutu': _dbRow,
  'Alatalja': _seatedRow,
  'Soutu laitteessa': _seatedRow,
  'Leuanveto': _pullUp,
  'Leuanveto vastaotteella': _pullUp,
  'Ylätalja': _latPulldown,
  'Suorin käsin ylätalja': _straightArm,
  'Selän ojennus': _hyperext,
  'Hauiskääntö tangolla': _bbCurl,
  'Hauiskääntö käsipainoilla': _dbCurl,
  'Vasarakääntö': _dbCurl,
  'Hauiskääntö taljassa': _cableCurl,
  'Scott-kääntö': _preacher,
  'Ojentajapunnerrus taljassa': _pushdown,
  'Ranskalainen punnerrus': _skullcrusher,
  'Ojentajapunnerrus pään yli': _overheadExt,
  'Jalkaprässi': _legPress,
  'Reiden ojennus': _legExt,
  'Reiden koukistus': _legCurl,
  'Pohjenousu seisten': _calfStanding,
  'Pohjenousu istuen': _calfSeated,
  'Hip thrust': _hipThrust,
  'Askelkyykky': _lungeDb,
  'Askelkyykkykävely': _lungeDb,
  'Bulgarialainen askelkyykky': _bulgarian,
  'Farmer walk': _walk,
  'Lankku': _plank,
  'Vatsarutistus': _crunch,
  'Jalannosto roikkuen': _hangingRaise,
  'Kahvakuulaheilautus': _kbSwing,
  'Yhden käden heilautus': _kbSwing,
  'Kahvakuulamaastaveto': _kbDeadlift,
  'Kahvakuulan rinnalleveto': _kbClean,
  'Rinnalleveto ja punnerrus': _kbPress,
  'Kahvakuulatempaus': _kbSnatch,
  'Kahvakuulapystypunnerrus': _kbPress,
  'Lonkan loitonnus': _hipAbduction,
  'Lonkan lähennys': _hipAdduction,
  'Nordic hamstring': _nordic,
  'Kööpenhaminan lähennys': _copenhagen,
  'Kaapeliristikkäis': _cableCross,
  'Peck deck': _peckDeck,
  'Käsipainoaukaisu': _dbFly,
  'Olankohautus': _shrug,
  'Australialainen leuanveto': _invertedRow,
  'Vipunosto sivulle': _lateralRaise,
  'Vipunosto eteen': _frontRaise,
  'Takaolkavipunosto': _rearDelt,
  'Pystysoutu': _uprightRow,
  'Face pull': _facePull,
  'Vipunosto taljassa': _cableLateral,
  'Ulkokierto taljassa': _externalRotation,
  'Keskittynyt hauiskääntö': _concentrationCurl,
  'Ranteen koukistus': _wristCurl,
  'Ranteen ojennus': _wristExt,
  'Ab wheel': _abWheel,
  'Pallof press': _pallof,
  'Venäläinen twisti': _russianTwist,
  'Kaapelirutistus': _cableCrunch,
  'Kylkilankku': _sidePlank,
  'Ojentajaojennus kehonpainolla': _bwTricepsExt,
  'Kehonpainohauiskääntö': _bwCurl,
  'Burpee': _burpee,
  'Renegade-soutu': _renegade,
  'Turkkilainen ylösnousu': _getUp,
  'Tuulimylly': _windmill,
  'Kahvakuulan etukyykky': _kbFrontSquat,
  'Kahvakuulan sumomaastaveto': _kbDeadlift,
  'Kahvakuulan sumoveto': _kbHighPull,
  'Kahvakuulahauiskääntö': _kbCurl,
  'Kahvakuula-askelkyykky': _kbLunge,
  'Lentokone': _kbSingleLegRdl,
  'Tuplakahvakuulaheilautus': _kbSwing,
  'Tuplakahvakuulamaastaveto': _kbDeadlift,
  'Tuplakahvakuulan rinnalleveto': _kbClean,
  'Tuplakahvakuulapystypunnerrus': _kbPress,
  'Tuplakahvakuulatyöntö': _kbPress,
  'Tuplakahvakuulan rinnalleveto ja punnerrus': _kbPress,
  'Tuplakahvakuulasoutu': _kbRow,
  'Tuplakahvakuulalattiapunnerrus': _kbFloorPress,
  'Tuplakahvakuula-askelkyykky': _lungeDb,
  'Kahvakuula-thruster': _kbThruster,
  'Yhden jalan maastaveto': _kbSingleLegRdl,
  'Kahvakuulasoutu': _kbRow,
  'Kahvakuulalattiapunnerrus': _kbFloorPress,
  'Matkalaukkukanto': _suitcase,
  'Lantionnosto': _glueBridge,
  'Pistoolikyykky': _pistol,
  'Kyykky kehonpainolla': _airSquat,
  'Hyppykyykky': _jumpSquat,
  'Sissy-kyykky': _sissy,
  'Käänteinen nordic': _reverseNordic,
  'Askelnousu': _stepUp,
  'Jalat koholla punnerrus': _declinePushUp,
  'Timanttipunnerrus': _pushUp,
  'Pike-punnerrus': _pikePushUp,
  'Käsilläseisontapunnerrus': _hspu,
  'Yhden jalan lantionnosto': _singleLegBridge,
  'Reiden koukistus kehonpainolla': _bwLegCurl,
  'Veneasento': _hollow,
  'Dead bug': _deadBug,
  'Y-T-W-nostot makuulla': _ytw,
  'Superman-nosto': _superman,
  'Vinopunnerrus': _inclinePushUp,
  'Polvipunnerrus': _kneePushUp,
  'Negatiivinen leuanveto': _negativePullUp,
  'Kuminauhaleuanveto': _pullUp,
  'Roikunta': _deadHang,
  'Lapaluuveto roikkuen': _scapPull,
  'Seinäistunta': _wallSit,
  'Lintukoira': _birdDog,
  'Vuorikiipeilijä': _mountainClimber,
  'Karhukävely': _bearCrawl,
  'Yhden jalan pohjenousu': _calfStanding,
};
