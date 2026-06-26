import Foundation

func testSeverity() {
    T.eq(Severity(utilization: 0),  .green, "0% is green")
    T.eq(Severity(utilization: 15), .green, "15% is green")
    T.eq(Severity(utilization: 69), .green, "69% is green")
    T.eq(Severity(utilization: 70), .amber, "70% is amber")
    T.eq(Severity(utilization: 89), .amber, "89% is amber")
    T.eq(Severity(utilization: 90), .red,   "90% is red")
    T.eq(Severity(utilization: 100), .red,  "100% is red")
}
