"""Invariant checks for the generated Playtest static-evidence artifacts."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "data/playtest-static-pose-evidence-v1.json"
EXPORTS = ROOT / "data/playtest-static-pose-export-manifest-v1.json"


def main() -> None:
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    exports = json.loads(EXPORTS.read_text(encoding="utf-8"))
    coverage = evidence["coverage"]
    nonhuman = evidence["nonhuman"]
    female_female = evidence["femaleFemale"]

    assert coverage["tableFamilyCount"] == 508
    assert coverage["nonhumanFamilyCount"] == len(nonhuman) == 227
    assert coverage["femaleFemaleFamilyCount"] == len(female_female) == 31
    assert coverage["allEntriesFormalRuleStatus"] == "not_generated"
    assert evidence["sources"]["table"]["sourceAsset"] == "/Game/Data/TableHAnim"
    assert evidence["sources"]["packageList"]["game"] == "love"
    assert evidence["sources"]["packageList"]["scannedPaks"] == ["Pak1.pak", "Pak2.pak", "Pak3.pak", "Pak4.pak", "Pak5.pak"]
    assert all(row["formalRuleStatus"] == "not_generated" for row in nonhuman + female_female)
    assert all(row["exactMontageEvidence"]["monsterPackagePaths"] for row in nonhuman)
    assert all(not row["exactMontageEvidence"]["unindexedMonsterPackagePaths"] for row in nonhuman)
    assert all(len(row["participants"]) >= 2 for row in female_female)

    hound = [row for row in nonhuman if "Hound" in row["monsterDirectories"]]
    assert len(hound) == 36
    for row in hound:
        evidence_rows = [item for item in row["skeletonEvidence"] if item["monsterDirectory"] == "Hound"]
        if row["hanimeId"] == "AletHound_Mouth01":
            assert any(item["functionalBoneCandidates"] for item in evidence_rows)
        else:
            assert all(not item["functionalBoneCandidates"] for item in evidence_rows)
            assert all(item["axisSelection"] == "no_reference_candidate_without_family_evidence" for item in evidence_rows)

    assert len(exports["requests"]) >= len(nonhuman)
    assert all(request["noOverwrite"] for request in exports["requests"])
    assert all(request["formalRuleStatus"] == "not_generated" for request in exports["requests"])
    assert any(probe["kind"] == "AnimMontage" and "0/0" in probe["result"] for probe in exports["validatedCliProbes"])
    for request in exports["requests"]:
        response = ROOT / request["responseFile"]
        assert response.exists(), response
        assert "-nooverwrite" in response.read_text(encoding="utf-8")

    print(f"validated {len(nonhuman)} nonhuman, {len(female_female)} female/female and {len(exports['requests'])} response files")


if __name__ == "__main__":
    main()
