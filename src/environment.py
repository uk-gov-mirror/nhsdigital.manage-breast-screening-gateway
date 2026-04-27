import os
from enum import Enum


class Envs(Enum):
    DEVELOPMENT = "dev"
    REVIEW = "review"
    PREPROD = "preprod"
    PRODUCTION = "prod"


class Environment:
    @property
    def development(self) -> bool:
        return self.environment == Envs.DEVELOPMENT.value

    @property
    def production(self) -> bool:
        return self.environment == Envs.PRODUCTION.value

    @property
    def review(self) -> bool:
        return self.environment == Envs.REVIEW.value

    @property
    def preprod(self) -> bool:
        return self.environment == Envs.PREPROD.value

    @property
    def environment(self) -> str:
        env = os.getenv("ENVIRONMENT")
        if not env or env.lower() not in (e.value for e in Envs):
            return Envs.DEVELOPMENT.value
        else:
            return os.getenv("ENVIRONMENT", Envs.DEVELOPMENT.value).lower()
