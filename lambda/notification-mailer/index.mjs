// 개인 알림(회원가입 이메일 인증번호, 예매확정/취소) 발송 Lambda — 원래 modules/messaging 전용
// 모듈 안에 있던 코드를 범용 modules/lambda가 참조하는 위치(Infra/lambda/)로 옮김.
// 큐를 여러 개 만들 필요 없이 메시지의 type 필드로 어떤 알림인지 구분해서 템플릿만 갈아끼우는 구조.
import {
  SESv2Client,
  SendEmailCommand,
} from "@aws-sdk/client-sesv2";

const sesClient = new SESv2Client({
  region: process.env.AWS_REGION,
});

// type이 없는 메시지(기존 회원가입 인증 형태 {email, code})는 EMAIL_VERIFICATION으로 취급 — 하위 호환
const TEMPLATES = {
  EMAIL_VERIFICATION: (b) => {
    if (!b.email || !b.code) {
      throw new Error(`email 또는 code가 없습니다: ${JSON.stringify(b)}`);
    }
    return {
      subject: "[Qket] 이메일 인증번호",
      text:
        `Qket 이메일 인증번호입니다.\n\n` +
        `인증번호: ${b.code}\n\n` +
        `인증번호는 5분 동안 유효합니다.`,
    };
  },
  RESERVATION_CONFIRMED: (b) => ({
    subject: "[Qket] 예매가 확정되었습니다",
    text:
      `${b.performanceTitle} 예매가 확정되었습니다.\n\n` +
      `공연 일시: ${b.roundTime}\n좌석: ${b.seatInfo}\n\n예매해주셔서 감사합니다.`,
  }),
  RESERVATION_CANCELLED: (b) => ({
    subject: "[Qket] 예매가 취소되었습니다",
    text:
      `${b.performanceTitle} 예매가 취소되었습니다.\n\n` +
      `공연 일시: ${b.roundTime}\n좌석: ${b.seatInfo}\n\n취소 처리가 완료되었습니다.`,
  }),
};

export const handler = async (event) => {
  console.log("SQS 이벤트:", JSON.stringify(event));

  for (const record of event.Records) {
    const body = JSON.parse(record.body);
    const type = body.type || "EMAIL_VERIFICATION";
    const templateFn = TEMPLATES[type];

    if (!body.email || !templateFn) {
      throw new Error(`알 수 없는 type 또는 email 누락: ${JSON.stringify(body)}`);
    }

    const { subject, text } = templateFn(body);

    const command = new SendEmailCommand({
      FromEmailAddress: process.env.FROM_EMAIL,

      Destination: {
        ToAddresses: [body.email],
      },

      Content: {
        Simple: {
          Subject: {
            Data: subject,
            Charset: "UTF-8",
          },

          Body: {
            Text: {
              Data: text,
              Charset: "UTF-8",
            },
          },
        },
      },
    });

    const response = await sesClient.send(command);

    console.log("이메일 발송 성공:", {
      type,
      email: body.email,
      messageId: response.MessageId,
    });
  }
};
