# Legal, Licensing, and Preservation Policies

This document outlines the legal compliance architecture, open-source licensing boundaries, and historical preservation frameworks governing the **RomWBW** ecosystem. 

---

## 1. Core System Firmware & Build Infrastructure

### 1.1 Project Source Code Licensing
Unless otherwise explicitly stated in the source headers, all low-level system firmware, HBIOS routines, build infrastructure automation scripts, and integration utilities authored directly for this ecosystem are officially licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**. 
* Any modifications, extensions, or downstream derivatives of the core RomWBW framework published to the network must adhere strictly to the copyleft requirements set forth in the AGPL-3.0 text.

### 1.2 Operating System Components
The underlying operating system targets built, configured, and deployed by this environment (including Digital Research CP/M 2.2, CP/M 3.0, and the Z-System framework) utilize legacy source code assets that have been formally released by their respective modern intellectual property successors under permissive open-source frameworks (specifically the **3-Clause BSD License**). These components are integrated legally and transparently into the upstream compilation pipeline.

---

## 2. Supplemental Testing, Validation, & Application Targets

### 2.1 The Principle of "Mere Aggregation"
The pre-compiled binary disk images distributed within release assets or snapshot configurations represent a technical **aggregate** of software. In strict alignment with open-source licensing frameworks (such as the Free Software Foundation guidelines), the inclusion of independent legacy applications residing on separate virtual file tracks does not extend the AGPL-3.0 copyleft requirements to those individual applications, nor does it imply a unified software product. 

### 2.2 Engineering Intent & Scope
Certain historic 8-bit utility binaries (such as legacy text editors, debuggers, compilers, and interpreted BASIC environments) are included on pre-compiled storage volumes strictly as an **educational and engineering convenience**. 
* **Hardware Validation:** These binaries act as immutable baseline workloads to validate complex low-level CPU instruction sets, benchmark execution efficiency across Z80/Z180/Z280 microprocessors, profile serial terminal emulation timings, and stress-test physical disk controller storage read/write routines.
* **Non-Commercial Context:** This project operates strictly as a non-profit, non-commercial open-source collective. No revenue is generated, no advertisements are hosted, and no access fees are charged. The included software represents obsolete architectures from decades past that carry zero active commercial market presence or modern retail availability.

---

## 3. Notice to Verified Intellectual Property Rights Holders

The maintainers of this repository proactively respect active copyright laws and closely track the modern evolution of legacy software preservation (such as the formal open-sourcing of historic 8-bit architectures like GW-BASIC and 6502 Microsoft BASIC under the MIT License). 

If you are a verified copyright holder, a corporate legal successor, or an authorized representative of a legacy utility bundled within these testing files, and you object to its inclusion as an archive or validation target:

1. **Direct Resolution Path:** Please open a formal inquiry via the GitHub Issue tracker or contact the repository administrator directly at **[Insert Your Dedicated Project Email Here]**.
2. **Commitment to Compliance:** Upon validation of identity and ownership, any requested assets will be promptly modified, obfuscated, or completely extracted from future build configurations and release packages without requiring platform escalation or formal administrative overhead.

---

## 4. Fork Policy and Platform Terms

Downstream forks of this project are independent workspaces managed by their respective account owners. 
* The upstream canonical repository project assumes zero operational or legal liability for any unapproved modifications, third-party software bundles, commercial exploitation attempts, or platform Terms of Service (ToS) violations committed independently by downstream fork operators. 
* Any administrative actions or platform disputes originating within a downstream fork remain strictly isolated to that specific node.
