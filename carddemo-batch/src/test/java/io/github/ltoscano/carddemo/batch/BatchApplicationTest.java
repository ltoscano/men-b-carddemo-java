package io.github.ltoscano.carddemo.batch;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

// Con due job (installationCheckJob e READACCT, issue #67) ogni avvio indica il job: qui quello che il
// test eseguiva gia'.
@SpringBootTest(properties = "spring.batch.job.name=installationCheckJob")
@ActiveProfiles("test")
class BatchApplicationTest {

    @Test
    void ilContestoSiAvvia() {
    }
}
