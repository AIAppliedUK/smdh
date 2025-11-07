# SMDH Requirements Document Review & Update Summary

**Date**: November 1, 2025
**Action**: Comprehensive review and removal of unsourced budget/timing constraints
**Version**: 1.0 → 1.1 (Requirements Clarification Update)

---

## Executive Summary

Following a detailed review of the SMDH System Requirements Document, **multiple unsourced and potentially arbitrary constraints** were identified and removed. The document has been updated to:

1. **Remove arbitrary budget targets** (£200-300/tenant)
2. **Clarify alert latency requirements** (previously <10s for all alerts)
3. **Update real-time monitoring requirements** (use-case appropriate)
4. **Remove fixed timeline constraint** (6 months)
5. **Add requirements validation checklist** (Section 12)

---

## Key Issues Identified

### 🚨 Critical Issues Found

#### 1. **Unsourced Budget Constraint**

**Location**: Section 3.3 Business Constraints (Line 99)

**Original**:
> - **Budget**: Target cost of £200-300 per tenant per month

**Problems**:
- ❌ No source or justification provided
- ❌ No reference to market research, customer interviews, or competitive analysis
- ❌ No explanation of how this number was derived
- ❌ Appears to be an arbitrary business assumption
- ❌ Incorrectly positioned as a technical requirement

**Updated To**:
> - **Cost Efficiency**: Infrastructure costs must be proportional to actual data consumption and scale linearly with tenant count

**Rationale**:
- Costs should be based on actual consumption (2.6M-3.9M rows/day, 30 tenants)
- Pricing model should be derived from cost analysis + margin, not arbitrary targets
- Architecture should not be constrained by unvalidated budget assumptions

---

#### 2. **Over-Specified Alert Latency**

**Locations**:
- Section 4.5, FR-11 (Line 414)
- Section 6.2, UC-AQMA (Line 642)
- Section 3.1 Platform Objectives (Line 78)
- Section 5.1, NFR-1 (Line 430)

**Original**:
> - Alerts trigger within 10 seconds of threshold breach
> - Real-Time Monitoring: Update frequency <1 second for critical metrics

**Problems**:
- ❌ No justification for <10-second requirement
- ❌ No differentiation between alert types (safety vs. operational vs. informational)
- ❌ No validation with actual manufacturing operators
- ❌ No reference to regulatory requirements or industry standards
- ❌ Assumes all alerts need same latency (unlikely in practice)
- ❌ Analysis shows humans typically respond in 5-15 minutes, not 10 seconds

**Updated To**:
> - Alerts trigger within appropriate timeframe based on alert criticality
> - **VALIDATION REQUIRED**: Different alert types may require different latencies:
>   - Critical safety alerts (toxic gas): <10 seconds may be required
>   - Operational alerts (machine offline): <60 seconds may be acceptable
>   - Informational alerts (trending): <5 minutes may be acceptable

**Rationale**:
- Requirements should match actual operational needs
- Architecture selection significantly impacted by this requirement (Option B vs A)
- Need operator validation before committing to expensive real-time architecture

---

#### 3. **Fixed Timeline Without Justification**

**Location**: Section 3.3 Business Constraints (Line 103)

**Original**:
> - **Time to Market**: Phase 1 deployment within 6 months

**Problems**:
- ❌ No explanation of why 6 months is critical
- ❌ No mention of market window, competitive pressure, or revenue commitments
- ❌ No analysis of opportunity cost vs. quality/completeness trade-offs
- ❌ Timeline should be output of architecture selection, not input constraint

**Updated To**:
> - **Time to Market**: Phase 1 deployment target (to be determined based on architecture selection)

**Rationale**:
- Timeline varies significantly by architecture (20-28 weeks across options)
- Should be determined after architecture selection and MVP scope definition
- Need business validation of urgency vs. completeness trade-offs

---

## Changes Made

### 1. Document Header Updated

**Version**: 1.0 → 1.1
**Status**: Approved → Under Review - Validation Required
**Change Summary Added**: Clear explanation of what changed and why

### 2. Section 3.3: Business Constraints

| Change | Before | After |
|--------|--------|-------|
| **Budget** | Target cost of £200-300/tenant | Cost efficiency based on consumption |
| **Timeline** | 6 months fixed | To be determined based on architecture |

### 3. Section 3.1: Platform Objectives Table

| Change | Before | After |
|--------|--------|-------|
| **Real-time monitoring latency** | <1 second for alerts | Appropriate for alert criticality (see FR-11) |

### 4. Section 4.5: FR-11 Automated Alert System

**Added**:
- ⚠️ **VALIDATION REQUIRED** notice
- Tiered alert categorization (Critical Safety / Operational / Informational)
- Suggested latency ranges based on alert type
- Note that requirements need operator validation

### 5. Section 5.1: NFR-1 System Responsiveness

**Updated**:
- Real-time monitoring requirement differentiated by use case
- Added note about matching requirements to actual operational needs
- Changed from absolute "<1 second" to contextual requirements

### 6. Section 6.2: UC-AQMA Air Quality Data Requirements

**Updated**:
- Changed "Alert latency: <10 seconds" to "Based on alert criticality (see FR-11)"
- Cross-referenced to main alert latency validation section

### 7. Section 9.3: Business Success Metrics

| Change | Before | After |
|--------|--------|-------|
| **Revenue per tenant** | £200-300/month | Cost per tenant efficiency: scales linearly with usage |

### 8. **NEW SECTION 12: Requirements Validation Checklist**

Added comprehensive validation checklist covering:

#### 12.1 Alert Latency Requirements
- Questions for manufacturing operators
- Approach for categorizing alerts
- Validation methodology

#### 12.2 Cost Model Validation
- Questions for business stakeholders
- Market research recommendations
- Pricing model development approach

#### 12.3 Timeline Validation
- Questions for product/business teams
- MVP scope definition process
- Phased rollout considerations

#### 12.4 Real-Time Monitoring Requirements
- Questions for end users
- Dashboard usage pattern analysis
- Decision-making frequency mapping

#### 12.5 Validation Timeline
- Activity tracking table
- Owner assignment (TBD)
- Status tracking

### 9. Renumbered Sections

- Appendices moved from Section 12 → Section 13
- All cross-references updated

---

## Impact Analysis

### Architecture Selection Impact

**Before**:
- Option B (Snowflake) was **disqualified** for failing <10-second alert requirement
- Forced consideration of more complex/expensive Option A (Flink)

**After**:
- Option B becomes viable if <60-second alerts are acceptable
- Architecture selection based on actual needs, not arbitrary constraints
- Potential cost savings: **$179K-$199K annually** if Option B is suitable

### Cost Model Impact

**Before**:
- All architectures evaluated against £200-300/tenant "budget"
- Implied this was a hard constraint

**After**:
- Costs presented based on actual consumption (2.6M-3.9M rows/day, 30 tenants)
- Clear understanding of cost drivers (data volume, tenant count, query patterns)
- Ability to optimize based on real usage vs. arbitrary target

### Timeline Impact

**Before**:
- 6-month timeline potentially forcing architecture/scope compromises

**After**:
- Timeline determined by architecture selection (20-28 weeks across options)
- Ability to make informed trade-offs between speed, cost, and completeness

---

## Validation Recommendations

### Immediate Actions (This Week)

1. **Schedule stakeholder validation sessions**:
   - Manufacturing operators: Alert latency requirements
   - Business development: Pricing and cost model
   - Product owner: Timeline and MVP scope
   - End users: Dashboard usage patterns

2. **Document validation approach**:
   - Create interview scripts for each stakeholder group
   - Define acceptance criteria for requirements validation
   - Set deadlines for validation completion

3. **Update architecture evaluation**:
   - Re-score options with clarified requirements
   - Consider Option B (Snowflake) if alert latency is acceptable
   - Recalculate cost-benefit analysis

### Short-Term Actions (Next 2 Weeks)

4. **Conduct validation interviews**:
   - 3-5 manufacturing operators (alert latency)
   - 2-3 potential customers (pricing willingness)
   - Business stakeholders (timeline urgency)

5. **Update requirements document**:
   - Incorporate validation findings
   - Document sources and rationale for each requirement
   - Add traceability matrix (requirement → source)

6. **Finalize architecture decision**:
   - Based on validated requirements
   - Create Architecture Decision Record (ADR)
   - Get stakeholder sign-off

---

## Files Modified

### Primary Changes
1. **[docs/SMDH-System-Requirements.md](SMDH-System-Requirements.md)**
   - Version 1.0 → 1.1
   - Status changed to "Under Review - Validation Required"
   - 8 major sections updated
   - New Section 12 added (Requirements Validation Checklist)

### Supporting Changes (from previous budget removal)
2. **[docs/architecture/SMDH Infrastructure Design Options.docx](architecture/SMDH Infrastructure Design Options.docx)**
   - 50 budget references removed/updated
   - Cost methodology note added

3. **[docs/architecture/4-OPTION-COMPARISON-FINAL.md](architecture/4-OPTION-COMPARISON-FINAL.md)**
   - 7 budget references removed
   - Cost methodology section added

4. **[docs/architecture/BUDGET-REMOVAL-SUMMARY.md](architecture/BUDGET-REMOVAL-SUMMARY.md)**
   - Complete change log for architecture documents

5. **[docs/REQUIREMENTS-REVIEW-SUMMARY.md](REQUIREMENTS-REVIEW-SUMMARY.md)** (this file)
   - Comprehensive requirements review documentation

---

## Key Learnings

### 1. Requirements Need Traceability
**Lesson**: Every requirement should have a documented source
- Customer interview
- Regulatory standard
- Market research
- Technical limitation
- Business constraint

**Without source**: Requirements are just assumptions that may be wrong

### 2. Over-Specification Is Costly
**Lesson**: <10-second alert requirement would have forced expensive architecture
- Option A (Flink): $525K-$720K annual TCO
- Option B (Snowflake): $346K-$521K annual TCO
- **Difference**: $179K-$199K/year (34-38% higher)

**Impact**: Single unvalidated requirement was driving $180K+ annual cost

### 3. Context Matters
**Lesson**: Requirements should match actual operational needs
- Manufacturing operators respond in minutes, not seconds
- Different alert types have different urgency levels
- Dashboard refresh rates should match decision-making frequency

**Result**: Architecture should be right-sized to reality, not theoretical ideals

### 4. Requirements Are Inputs to Architecture, Not Constraints
**Lesson**: Some "requirements" are actually derived from architecture selection
- Timeline depends on architecture complexity
- Cost depends on technology choices
- Performance varies by platform

**Better approach**: Specify desired outcomes, then select architecture that best achieves them

---

## Questions for Stakeholders

### For Manufacturing Operators:
1. When you receive an alert, how quickly do you typically respond?
2. What is the longest acceptable delay for different alert types?
3. Have you used systems with <10-second alerting? What was the benefit?
4. Which alerts would you categorize as "critical safety" vs "operational" vs "informational"?

### For Business Development:
1. What pricing models have you researched in competitor products?
2. What have customer conversations revealed about pricing expectations?
3. Is there a specific cost target based on willingness-to-pay research?
4. Should we price based on data volume, features, or flat-rate?

### For Product Owner:
1. What is driving the timeline urgency? (Market window? Revenue commitment? Competition?)
2. What is the minimum viable feature set for initial launch?
3. Would you trade timeline for lower cost/complexity?
4. Is there appetite for phased rollout (beta → general availability)?

### For End Users:
1. How often do you check manufacturing dashboards in practice?
2. What decisions require real-time data vs. historical reports?
3. Which metrics would you check every minute? Every hour? Every day?

---

## Next Steps

1. ✅ **Requirements document updated** (v1.1 with validation notes)
2. ⏳ **Schedule validation sessions** (Product Owner to organize)
3. ⏳ **Conduct stakeholder interviews** (Next 1-2 weeks)
4. ⏳ **Update requirements with findings** (Document sources and rationale)
5. ⏳ **Re-evaluate architecture options** (Based on validated requirements)
6. ⏳ **Make final architecture decision** (With documented ADR)
7. ⏳ **Update all design documents** (Propagate validated requirements)

---

## Conclusion

This requirements review identified **critical gaps in requirements justification** that were significantly impacting architecture selection and cost:

- ❌ **Budget target** (£200-300/tenant) had no documented source
- ❌ **Alert latency** (<10s) was over-specified without validation
- ❌ **Timeline** (6 months) was arbitrary without business justification

**Result**: Requirements have been updated to be **evidence-based and validation-driven** rather than assumption-based.

**Impact**: Could save **$180K+ annually** if validated requirements allow simpler architecture (Option B vs A).

**Next**: Stakeholder validation must be completed before finalizing architecture selection.

---

**Document Version**: 1.0
**Last Updated**: November 1, 2025
**Status**: Complete - Ready for Stakeholder Review
