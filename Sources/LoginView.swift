import SwiftUI

struct LoginView: View {
    @Binding var isLoggedIn: Bool
    @State private var taiKhoan = Prefs.lastTaiKhoan
    @State private var matKhau = "123456"
    @State private var showMatKhau = false
    @State private var loading = false
    @State private var errorText: String?
    @FocusState private var focusedField: Field?
    /// Chụp lại 1 lần lúc mở màn hình — tránh đổi giao diện giữa chừng nếu login tự động fail rồi
    /// set errorText (không được nhảy sang chế độ "thủ công" chỉ vì có lỗi, vẫn phải hiện form).
    @State private var manualMode = Prefs.manualLogout

    private enum Field { case taiKhoan, matKhau }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.brandPrimary, Color.brandPrimary.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // ScrollView (thay vì VStack trần) để SwiftUI tự tránh bàn phím - VStack đứng riêng
            // trong ZStack KHÔNG được hệ thống tự đẩy lên khi bàn phím hiện.
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 40)

                    logoHeader
                        .padding(.bottom, 32)

                    VStack(spacing: 22) {
                        if let errorText {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(errorText)
                            }
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.red)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        }

                        if manualMode {
                            manualForm
                        } else {
                            VStack(spacing: 14) {
                                ProgressView()
                                    .controlSize(.large)
                                    .tint(.brandPrimary)
                                Text("Đang đăng nhập...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 12)
                    )
                }
                .padding(28)
                .frame(maxWidth: 400)
                .frame(maxWidth: .infinity)
            }
        }
        .task {
            if !manualMode && !RuntimeEnv.isRunningUnitTests {
                await doLogin()
            }
        }
    }

    private var logoHeader: some View {
        VStack(spacing: 8) {
            Text("Đenn Coffee")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Quán nhỏ cảm ơn to")
                .font(.subheadline.weight(.medium))
                .opacity(0.85)
        }
        .foregroundColor(.white)
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }

    private var manualForm: some View {
        VStack(spacing: 16) {
            fieldContainer(icon: "person.fill", isFocused: focusedField == .taiKhoan) {
                TextField("Tài khoản", text: $taiKhoan)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .focused($focusedField, equals: .taiKhoan)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .matKhau }
            }

            fieldContainer(icon: "lock.fill", isFocused: focusedField == .matKhau) {
                Group {
                    if showMatKhau {
                        TextField("Mật khẩu", text: $matKhau)
                    } else {
                        SecureField("Mật khẩu", text: $matKhau)
                    }
                }
                .focused($focusedField, equals: .matKhau)
                .submitLabel(.go)
                .onSubmit { Task { await doLogin() } }

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showMatKhau.toggle() }
                } label: {
                    Image(systemName: showMatKhau ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.secondary)
                }
            }

            Button {
                Task { await doLogin() }
            } label: {
                ZStack {
                    if loading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Đăng nhập")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .foregroundColor(.white)
            .background(
                (taiKhoan.isEmpty || matKhau.isEmpty || loading) ? Color.brandPrimary.opacity(0.35) : Color.brandPrimary,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .shadow(
                color: Color.brandPrimary.opacity((taiKhoan.isEmpty || matKhau.isEmpty || loading) ? 0 : 0.35),
                radius: 12, x: 0, y: 6
            )
            .disabled(loading || taiKhoan.isEmpty || matKhau.isEmpty)
            .animation(.easeInOut(duration: 0.15), value: taiKhoan.isEmpty || matKhau.isEmpty)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func fieldContainer<Content: View>(icon: String, isFocused: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(isFocused ? .brandPrimary : .secondary)
                .frame(width: 20)
            content()
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isFocused ? Color.brandPrimary : Color(.separator).opacity(0.4), lineWidth: isFocused ? 1.5 : 1)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }

    private func doLogin() async {
        guard !taiKhoan.isEmpty, !matKhau.isEmpty else {
            errorText = "Nhập tài khoản và mật khẩu."
            return
        }
        loading = true
        errorText = nil
        let result = await APIClient.shared.login(taiKhoan: taiKhoan, matKhau: matKhau)
        loading = false
        switch result {
        case .success(let resp):
            guard let token = resp.token else {
                errorText = "Phản hồi từ server không hợp lệ."
                return
            }
            Prefs.lastTaiKhoan = taiKhoan
            Prefs.saveSession(token: token, refreshToken: resp.refreshToken, displayName: resp.tenHienThi)
            isLoggedIn = true
        case .rejected(let message):
            errorText = message
            // Auto-login thất bại (vd server đổi mật khẩu mặc định) — chuyển sang form thủ công
            // thay vì đứng yên với 1 spinner vô nghĩa không ai bấm được gì.
            if !manualMode { manualMode = true }
        case .networkError:
            errorText = "Không kết nối được server, thử lại sau."
            if !manualMode { manualMode = true }
        }
    }
}
