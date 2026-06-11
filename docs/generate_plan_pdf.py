# -*- coding: utf-8 -*-
"""자람(Jaram) 앱 개요 및 운영 계획서 PDF 생성."""

from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_JUSTIFY
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    PageBreak,
    KeepTogether,
)

# ── 한글 폰트 등록 (Windows 기본 폰트 사용) ──
pdfmetrics.registerFont(TTFont("Malgun", "C:/Windows/Fonts/malgun.ttf"))
pdfmetrics.registerFont(TTFont("MalgunBold", "C:/Windows/Fonts/malgunbd.ttf"))

OUTPUT = "C:/dev/pbs_plus/docs/자람_앱_운영계획서.pdf"

# ── 색상 ──
JARAM_GREEN = colors.HexColor("#10B981")
NAVY = colors.HexColor("#1E3A8A")
LIGHT_BG = colors.HexColor("#F0FDF4")
GRAY = colors.HexColor("#6B7280")
LIGHT_GRAY = colors.HexColor("#E5E7EB")

# ── 스타일 ──
styles = getSampleStyleSheet()

H_TITLE = ParagraphStyle(
    "HTitle",
    parent=styles["Title"],
    fontName="MalgunBold",
    fontSize=22,
    leading=30,
    alignment=TA_CENTER,
    textColor=NAVY,
    spaceAfter=8,
)
H_SUBTITLE = ParagraphStyle(
    "HSubtitle",
    fontName="Malgun",
    fontSize=12,
    leading=18,
    alignment=TA_CENTER,
    textColor=GRAY,
    spaceAfter=20,
)
H1 = ParagraphStyle(
    "H1",
    fontName="MalgunBold",
    fontSize=15,
    leading=22,
    textColor=NAVY,
    spaceBefore=14,
    spaceAfter=6,
    borderPadding=6,
    leftIndent=0,
)
H2 = ParagraphStyle(
    "H2",
    fontName="MalgunBold",
    fontSize=12,
    leading=18,
    textColor=JARAM_GREEN,
    spaceBefore=10,
    spaceAfter=4,
)
BODY = ParagraphStyle(
    "Body",
    fontName="Malgun",
    fontSize=10.5,
    leading=17,
    alignment=TA_JUSTIFY,
    textColor=colors.black,
    spaceAfter=4,
)
BULLET = ParagraphStyle(
    "Bullet",
    fontName="Malgun",
    fontSize=10.5,
    leading=17,
    leftIndent=14,
    bulletIndent=0,
    spaceAfter=2,
)
NOTE = ParagraphStyle(
    "Note",
    fontName="Malgun",
    fontSize=9,
    leading=13,
    textColor=GRAY,
    spaceAfter=4,
)

doc = SimpleDocTemplate(
    OUTPUT,
    pagesize=A4,
    leftMargin=22 * mm,
    rightMargin=22 * mm,
    topMargin=22 * mm,
    bottomMargin=22 * mm,
    title="자람(Jaram) 앱 개요 및 운영 계획서",
    author="신창용 (충암중학교)",
)

story = []

# ── 표지 ──
story.append(Spacer(1, 30 * mm))
story.append(Paragraph("자람(Jaram)", H_TITLE))
story.append(Paragraph("앱 개요 및 운영 계획서", H_TITLE))
story.append(Spacer(1, 6 * mm))
story.append(Paragraph("─ 학교차원 긍정적 행동지원(SWPBS) ─", H_SUBTITLE))
story.append(Paragraph("일일 행동 자기점검 모바일 애플리케이션", H_SUBTITLE))

story.append(Spacer(1, 50 * mm))

cover_info = [
    ["사 업 명", "자람(Jaram) SWPBS 행동 자기점검 앱"],
    ["대 상", "전교생 및 교직원"],
    ["담  당", "신창용 (충암중학교 도덕과)"],
    ["시행 시기", "2026학년도 1학기 ~ "],
    ["문서 작성일", "2026. 6. 11."],
]
cover_tbl = Table(cover_info, colWidths=[35 * mm, 110 * mm])
cover_tbl.setStyle(
    TableStyle(
        [
            ("FONTNAME", (0, 0), (-1, -1), "Malgun"),
            ("FONTNAME", (0, 0), (0, -1), "MalgunBold"),
            ("FONTSIZE", (0, 0), (-1, -1), 11),
            ("TEXTCOLOR", (0, 0), (0, -1), NAVY),
            ("BACKGROUND", (0, 0), (0, -1), LIGHT_BG),
            ("GRID", (0, 0), (-1, -1), 0.6, LIGHT_GRAY),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("LEFTPADDING", (0, 0), (-1, -1), 10),
            ("RIGHTPADDING", (0, 0), (-1, -1), 10),
            ("TOPPADDING", (0, 0), (-1, -1), 8),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
        ]
    )
)
story.append(cover_tbl)
story.append(PageBreak())

# ── 1. 추진 배경 ──
story.append(Paragraph("Ⅰ. 추진 배경 및 필요성", H1))
story.append(
    Paragraph(
        "학교차원 긍정적 행동지원(SWPBS, School-Wide Positive Behavior Support)은 "
        "처벌 중심의 생활지도에서 벗어나 학생의 긍정적 행동을 강화하는 학교 운영 모델로, "
        "미국·캐나다·호주 등에서 30여 년간 누적된 연구를 통해 효과성이 입증된 "
        "근거 기반(Evidence-Based) 접근입니다.",
        BODY,
    )
)
story.append(Spacer(1, 4))
story.append(Paragraph("□ 국내·외 연구 효과", H2))
research = [
    "· 학업 성취도 향상 (Horner et al., 2009 / Bradshaw et al., 2010)",
    "· 또래 관계 개선 및 학교 소속감 증대 (Sugai & Horner, 2006)",
    "· 학교폭력 및 징계 사건 평균 30~50% 감소 (Bradshaw et al., 2012)",
    "· 교사의 생활지도 스트레스 감소 및 수업 시간 확보 (Ross et al., 2012)",
]
for r in research:
    story.append(Paragraph(r, BULLET))

story.append(Spacer(1, 4))
story.append(Paragraph("□ 기존 종이 점검표의 한계", H2))
for r in [
    "· 매일 종이 점검표를 출력·배포·수합·집계하는 데 교사 업무 과중",
    "· 학생이 분실하거나 의무감으로만 표기 → 자기점검 본래 의미 퇴색",
    "· 학급·학년·전교 단위 종합 통계 산출 불가",
    "· 데이터 축적이 어려워 학교 단위 효과성 평가 곤란",
]:
    story.append(Paragraph(r, BULLET))

# ── 2. 앱 개요 ──
story.append(Paragraph("Ⅱ. 앱 개요", H1))

overview_tbl = Table(
    [
        ["앱 이름", "자람(Jaram)"],
        ["슬로건", "함께 자라는 우리 학교"],
        ["대상", "초·중·고등학교 학생 및 교직원"],
        ["플랫폼", "Android (Google Play) / iOS (App Store)"],
        ["비용", "무료 (광고 없음, 인앱결제 없음)"],
        ["언어", "한국어"],
        ["연령 등급", "전체 이용가 (만 14세 미만 보호자 동의 필수)"],
    ],
    colWidths=[30 * mm, 130 * mm],
)
overview_tbl.setStyle(
    TableStyle(
        [
            ("FONTNAME", (0, 0), (-1, -1), "Malgun"),
            ("FONTNAME", (0, 0), (0, -1), "MalgunBold"),
            ("FONTSIZE", (0, 0), (-1, -1), 10),
            ("TEXTCOLOR", (0, 0), (0, -1), colors.white),
            ("BACKGROUND", (0, 0), (0, -1), JARAM_GREEN),
            ("GRID", (0, 0), (-1, -1), 0.4, LIGHT_GRAY),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("LEFTPADDING", (0, 0), (-1, -1), 8),
            ("TOPPADDING", (0, 0), (-1, -1), 6),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ]
    )
)
story.append(overview_tbl)

# ── 3. 주요 기능 ──
story.append(Paragraph("Ⅲ. 주요 기능", H1))

story.append(Paragraph("□ 학생용 기능", H2))
for r in [
    "· <b>일일 행동 자기점검</b> : 학교가 정한 SWPBS 3대 가치 (책임·존중·배려) 기반 항목을 매일 O/X로 점검",
    "· <b>포인트 적립</b> : 일일 점검 완료 시 100P, 1주 연속 시 보너스 500P",
    "· <b>학교 상점 교환</b> : 적립 포인트로 학교가 정한 강화물(간식·문구·특권 등) 교환",
    "· <b>학교 점수 경쟁</b> : 학급 → 학년 → 전교 → 전국 자람 사용 학교 간 점수 비교",
    "· <b>뱃지 시스템</b> : 연속 점검·고득점·항목별 성장 등 다양한 뱃지로 동기 부여",
    "· <b>성장 그래프</b> : 개인의 행동 추이를 주간·월간 차트로 시각화",
]:
    story.append(Paragraph(r, BULLET))

story.append(Spacer(1, 4))
story.append(Paragraph("□ 교사용 기능", H2))
for r in [
    "· <b>학급 대시보드</b> : 담임 학급 학생들의 점검 현황·평균 점수·취약 항목 실시간 확인",
    "· <b>학생 개별 조회</b> : 학생별 성장 추이·뱃지·포인트 이력 열람",
    "· <b>규칙 편집(관리자 전용)</b> : 학교 SWPBS 점검 규칙 추가·수정·삭제",
    "· <b>상점 운영(관리자 전용)</b> : 강화물 등록·재고 관리·교환 승인",
    "· <b>공지사항 발송</b> : 학교·학급 단위 푸시 알림 발송",
    "· <b>학교 코드 발급</b> : 신규 가입자용 6자리 코드 QR 공유",
]:
    story.append(Paragraph(r, BULLET))

story.append(Spacer(1, 4))
story.append(Paragraph("□ 관리자(SWPBS 리더십팀) 권한 체계", H2))
role_tbl = Table(
    [
        ["역할", "권한", "지정 방식"],
        ["학교 관리자\n(admin)", "규칙·상점·공지 전체 편집 + 권한 부여", "최초 학교 등록 교사 자동 지정"],
        ["일반 교사\n(regular)", "학급 학생 조회·대시보드 열람", "학교 코드로 가입 시 자동 지정"],
        ["학생\n(student)", "자기 점검·포인트·상점 이용", "학교 코드로 가입"],
    ],
    colWidths=[30 * mm, 80 * mm, 50 * mm],
)
role_tbl.setStyle(
    TableStyle(
        [
            ("FONTNAME", (0, 0), (-1, -1), "Malgun"),
            ("FONTNAME", (0, 0), (-1, 0), "MalgunBold"),
            ("FONTSIZE", (0, 0), (-1, -1), 9.5),
            ("BACKGROUND", (0, 0), (-1, 0), NAVY),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("GRID", (0, 0), (-1, -1), 0.4, LIGHT_GRAY),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("ALIGN", (0, 0), (-1, 0), "CENTER"),
            ("ALIGN", (0, 1), (0, -1), "CENTER"),
            ("LEFTPADDING", (0, 0), (-1, -1), 6),
            ("TOPPADDING", (0, 0), (-1, -1), 6),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ]
    )
)
story.append(role_tbl)

# ── 4. 운영 계획 ──
story.append(PageBreak())
story.append(Paragraph("Ⅳ. 운영 계획", H1))

phase_tbl = Table(
    [
        ["단계", "시기", "주요 활동"],
        [
            "1. 준비 단계",
            "2026. 6.",
            "· 시범 학급 선정(1~2개 학급)\n"
            "· 교사 사전 연수(앱 설치·사용법)\n"
            "· 학교 SWPBS 규칙 입력\n"
            "· 학교 상점 강화물 등록",
        ],
        [
            "2. 시범 운영",
            "2026. 7.",
            "· 시범 학급 학생 가입·이용\n"
            "· 1차 만족도 조사\n"
            "· 규칙·강화물 보완",
        ],
        [
            "3. 전교 확대",
            "2026. 9. ~ 12.",
            "· 전교생 가입\n"
            "· 주간 우수 학급·학생 시상\n"
            "· 학부모 안내장 배부\n"
            "· 월별 학급별 성장 보고서",
        ],
        [
            "4. 평가·환류",
            "2027. 2.",
            "· 학기말 효과성 평가\n"
            "· 학생·교사·학부모 만족도 조사\n"
            "· 차년도 운영 방향 보고",
        ],
    ],
    colWidths=[30 * mm, 28 * mm, 102 * mm],
)
phase_tbl.setStyle(
    TableStyle(
        [
            ("FONTNAME", (0, 0), (-1, -1), "Malgun"),
            ("FONTNAME", (0, 0), (-1, 0), "MalgunBold"),
            ("FONTNAME", (0, 1), (0, -1), "MalgunBold"),
            ("FONTSIZE", (0, 0), (-1, -1), 10),
            ("BACKGROUND", (0, 0), (-1, 0), JARAM_GREEN),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("BACKGROUND", (0, 1), (1, -1), LIGHT_BG),
            ("GRID", (0, 0), (-1, -1), 0.4, LIGHT_GRAY),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("ALIGN", (0, 0), (-1, 0), "CENTER"),
            ("ALIGN", (0, 1), (1, -1), "CENTER"),
            ("LEFTPADDING", (0, 0), (-1, -1), 8),
            ("RIGHTPADDING", (0, 0), (-1, -1), 8),
            ("TOPPADDING", (0, 0), (-1, -1), 7),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
        ]
    )
)
story.append(phase_tbl)

# ── 5. 기대 효과 ──
story.append(Paragraph("Ⅴ. 기대 효과", H1))
for r in [
    "· <b>학생</b> : 매일의 자기점검 습관 형성으로 자기조절능력 및 책임감 향상",
    "· <b>학급</b> : 객관적 행동 지표를 통한 학급 운영 자료 확보",
    "· <b>학교</b> : 누적 데이터를 바탕으로 한 SWPBS 효과성 정량 평가 가능",
    "· <b>교사</b> : 종이 점검표 제작·집계 업무 대폭 경감 (주당 약 2시간 절감 예상)",
    "· <b>학부모</b> : 자녀의 학교 생활 행동 지표를 가정에서도 확인 가능",
]:
    story.append(Paragraph(r, BULLET))

# ── 6. 개인정보 보호 및 안전 조치 ──
story.append(Paragraph("Ⅵ. 개인정보 보호 및 안전 조치", H1))
story.append(Paragraph("□ 수집 정보 최소화", H2))
for r in [
    "· 이메일, 비밀번호(암호화), 닉네임, 학교 코드, 학년·반·번호만 수집",
    "· 사진·연락처·위치정보·마이크·카메라 등 민감 정보 일체 미수집",
]:
    story.append(Paragraph(r, BULLET))

story.append(Paragraph("□ 법적 준수 사항", H2))
for r in [
    "· 「개인정보 보호법」 및 시행령 전면 준수",
    "· <b>만 14세 미만 가입 시 법정대리인(보호자) 동의 절차 의무화</b>",
    "· 회원 탈퇴 시 개인정보 즉시 파기",
    "· 1년 이상 미접속 휴면 계정 자동 분리 보관",
]:
    story.append(Paragraph(r, BULLET))

story.append(Paragraph("□ 기술적 보안 조치", H2))
for r in [
    "· 비밀번호 단방향 암호화(bcrypt) 저장 → 운영자도 원본 확인 불가",
    "· 전 구간 SSL/TLS 통신 암호화",
    "· Supabase Row-Level Security(RLS) 정책으로 <b>학교 간 데이터 완전 격리</b>",
    "· 광고 추적 식별자(GAID/IDFA) 미수집, 제3자 광고 SDK 미포함",
]:
    story.append(Paragraph(r, BULLET))

# ── 7. 기술 사양 ──
story.append(PageBreak())
story.append(Paragraph("Ⅶ. 기술 사양 및 인프라", H1))

tech_tbl = Table(
    [
        ["구분", "사용 기술 / 서비스", "비고"],
        ["프론트엔드", "Flutter (Dart 3)", "Android·iOS 동시 지원"],
        ["백엔드 / DB", "Supabase (PostgreSQL)", "AWS Tokyo 리전"],
        ["인증", "Supabase Auth (이메일/비밀번호)", "bcrypt 암호화"],
        ["호스팅", "Supabase Cloud (Pro 플랜)", ""],
        ["배포 (Android)", "Google Play Console", "현재 운영 중"],
        ["배포 (iOS)", "App Store Connect + Codemagic CI/CD", "2026. 6. 출시 예정"],
        ["알림", "Flutter Local Notifications", "기기 내 로컬 알림"],
        ["통계 / 분석", "자체 PostgreSQL 집계", "외부 분석 도구 미사용"],
    ],
    colWidths=[35 * mm, 75 * mm, 50 * mm],
)
tech_tbl.setStyle(
    TableStyle(
        [
            ("FONTNAME", (0, 0), (-1, -1), "Malgun"),
            ("FONTNAME", (0, 0), (-1, 0), "MalgunBold"),
            ("FONTSIZE", (0, 0), (-1, -1), 9.5),
            ("BACKGROUND", (0, 0), (-1, 0), NAVY),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("BACKGROUND", (0, 1), (0, -1), LIGHT_BG),
            ("GRID", (0, 0), (-1, -1), 0.4, LIGHT_GRAY),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("ALIGN", (0, 0), (-1, 0), "CENTER"),
            ("LEFTPADDING", (0, 0), (-1, -1), 7),
            ("TOPPADDING", (0, 0), (-1, -1), 6),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ]
    )
)
story.append(tech_tbl)

# ── 8. 예산 ──
story.append(Paragraph("Ⅷ. 예산 계획", H1))
budget_tbl = Table(
    [
        ["항목", "내역", "금액(연)", "비고"],
        ["Supabase Pro", "데이터베이스 운영비", "약 30만 원", "월 $25 × 12"],
        ["Apple Developer", "iOS 앱 등록·갱신비", "약 13만 원", "$99/년"],
        ["Google Play", "Android 앱 등록비", "0 원", "1회성 $25 납부 완료"],
        ["도메인·이메일", "공식 안내용 (선택)", "약 2만 원", ""],
        ["총 운영비", "", "약 45만 원/년", ""],
    ],
    colWidths=[35 * mm, 55 * mm, 35 * mm, 35 * mm],
)
budget_tbl.setStyle(
    TableStyle(
        [
            ("FONTNAME", (0, 0), (-1, -1), "Malgun"),
            ("FONTNAME", (0, 0), (-1, 0), "MalgunBold"),
            ("FONTNAME", (0, -1), (-1, -1), "MalgunBold"),
            ("FONTSIZE", (0, 0), (-1, -1), 10),
            ("BACKGROUND", (0, 0), (-1, 0), JARAM_GREEN),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("BACKGROUND", (0, -1), (-1, -1), LIGHT_BG),
            ("GRID", (0, 0), (-1, -1), 0.4, LIGHT_GRAY),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("ALIGN", (0, 0), (-1, 0), "CENTER"),
            ("ALIGN", (2, 1), (2, -1), "RIGHT"),
            ("LEFTPADDING", (0, 0), (-1, -1), 8),
            ("TOPPADDING", (0, 0), (-1, -1), 6),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ]
    )
)
story.append(budget_tbl)
story.append(Spacer(1, 3))
story.append(
    Paragraph(
        "※ 운영비는 개발자(신창용) 자비 부담을 원칙으로 하며, 학교·교육청 단위 보급 확대 시 별도 협의.",
        NOTE,
    )
)

# ── 9. 추진 일정 ──
story.append(Paragraph("Ⅸ. 추진 일정", H1))
schedule_tbl = Table(
    [
        ["월", "주요 추진 사항"],
        ["2026. 5.", "앱 개발 완료 (Android Play Store 비공개 테스트)"],
        ["2026. 6.", "iOS App Store 등록·심사 / 시범 학급 운영 시작"],
        ["2026. 7.", "1차 만족도 조사·앱 개선"],
        ["2026. 8.", "여름방학 중 교사 연수 자료 제작"],
        ["2026. 9.", "전교생 확대 적용"],
        ["2026. 12.", "2학기 종합 성과 보고"],
        ["2027. 2.", "1차년도 효과성 평가 및 차년도 계획 수립"],
    ],
    colWidths=[30 * mm, 130 * mm],
)
schedule_tbl.setStyle(
    TableStyle(
        [
            ("FONTNAME", (0, 0), (-1, -1), "Malgun"),
            ("FONTNAME", (0, 0), (-1, 0), "MalgunBold"),
            ("FONTNAME", (0, 1), (0, -1), "MalgunBold"),
            ("FONTSIZE", (0, 0), (-1, -1), 10),
            ("BACKGROUND", (0, 0), (-1, 0), NAVY),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("BACKGROUND", (0, 1), (0, -1), LIGHT_BG),
            ("GRID", (0, 0), (-1, -1), 0.4, LIGHT_GRAY),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("ALIGN", (0, 0), (0, -1), "CENTER"),
            ("LEFTPADDING", (0, 0), (-1, -1), 8),
            ("TOPPADDING", (0, 0), (-1, -1), 6),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ]
    )
)
story.append(schedule_tbl)

# ── 10. 책임자 정보 ──
story.append(Paragraph("Ⅹ. 개발 및 운영 책임자", H1))
resp_tbl = Table(
    [
        ["성명", "신창용"],
        ["소속", "충암중학교 도덕과"],
        ["연락처", "godspeardragon@gmail.com"],
        ["역할", "앱 개발·운영·개인정보 보호 책임자"],
        ["근거 법령", "「개인정보 보호법」 제30조 (개인정보 처리방침의 수립 및 공개)"],
    ],
    colWidths=[30 * mm, 130 * mm],
)
resp_tbl.setStyle(
    TableStyle(
        [
            ("FONTNAME", (0, 0), (-1, -1), "Malgun"),
            ("FONTNAME", (0, 0), (0, -1), "MalgunBold"),
            ("FONTSIZE", (0, 0), (-1, -1), 10),
            ("TEXTCOLOR", (0, 0), (0, -1), NAVY),
            ("BACKGROUND", (0, 0), (0, -1), LIGHT_BG),
            ("GRID", (0, 0), (-1, -1), 0.4, LIGHT_GRAY),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("LEFTPADDING", (0, 0), (-1, -1), 10),
            ("TOPPADDING", (0, 0), (-1, -1), 7),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
        ]
    )
)
story.append(resp_tbl)

# ── 마지막 ──
story.append(Spacer(1, 20 * mm))
story.append(
    Paragraph(
        '"학생의 작은 성장이 모여, 학교 전체의 큰 변화를 만듭니다."',
        ParagraphStyle(
            "Quote",
            fontName="MalgunBold",
            fontSize=11,
            alignment=TA_CENTER,
            textColor=JARAM_GREEN,
            spaceAfter=4,
        ),
    )
)
story.append(
    Paragraph(
        "— 자람 (Jaram) —",
        ParagraphStyle(
            "QuoteFoot",
            fontName="Malgun",
            fontSize=10,
            alignment=TA_CENTER,
            textColor=GRAY,
        ),
    )
)


# ── 페이지 푸터 ──
def _footer(canvas, doc):
    canvas.saveState()
    canvas.setFont("Malgun", 8)
    canvas.setFillColor(GRAY)
    canvas.drawRightString(
        A4[0] - 22 * mm, 14 * mm, f"- {doc.page} -"
    )
    canvas.drawString(
        22 * mm, 14 * mm, "자람(Jaram) 앱 개요 및 운영 계획서"
    )
    canvas.setStrokeColor(LIGHT_GRAY)
    canvas.line(22 * mm, 17 * mm, A4[0] - 22 * mm, 17 * mm)
    canvas.restoreState()


doc.build(story, onFirstPage=_footer, onLaterPages=_footer)
print(f"OK -> {OUTPUT}")
