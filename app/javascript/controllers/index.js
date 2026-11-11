// Register controllers when their markup is on the page, so the storefront
// does not download every admin controller before the first paint.
import { application } from "controllers/application"
import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"
lazyLoadControllersFrom("controllers", application)
