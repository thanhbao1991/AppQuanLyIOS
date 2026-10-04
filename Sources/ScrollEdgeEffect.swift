import SwiftUI

/// iOS 26 Liquid Glass lam nav bar/toolbar tu dong chuyen filled<->translucent tuy theo co
/// content cuon duoi hay khong (xem community backlash ve do tuong phan khong on dinh — Apple
/// da phai them che do "Tinted" o 26.1 beta 4 de giam hieu ung nay). Ep .soft de nav bar luon
/// hien dang kinh/translucent mot kieu (giong luc list co data), tranh 2 man hinh (list rong vs
/// list co data) hien 2 style nut khac nhau.
/// scrollEdgeEffectStyle chi co tu iOS 26, deploymentTarget app la 16.0 nen phai gate qua #available.
private struct SoftScrollEdgeTopModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

extension View {
    func softScrollEdgeTop() -> some View {
        modifier(SoftScrollEdgeTopModifier())
    }
}
