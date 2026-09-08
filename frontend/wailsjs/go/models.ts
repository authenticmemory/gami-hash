export namespace app {
	
	export class ResumeInspection {
	    resumable: boolean;
	    root?: string;
	    rows: number;
	
	    static createFrom(source: any = {}) {
	        return new ResumeInspection(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.resumable = source["resumable"];
	        this.root = source["root"];
	        this.rows = source["rows"];
	    }
	}
	export class PreflightResult {
	    root: string;
	    output: string;
	    resume: ResumeInspection;
	    willResume: boolean;
	
	    static createFrom(source: any = {}) {
	        return new PreflightResult(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.root = source["root"];
	        this.output = source["output"];
	        this.resume = this.convertValues(source["resume"], ResumeInspection);
	        this.willResume = source["willResume"];
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	
	export class RunRequest {
	    root: string;
	    output: string;
	    workers: number;
	    mode: string;
	
	    static createFrom(source: any = {}) {
	        return new RunRequest(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.root = source["root"];
	        this.output = source["output"];
	        this.workers = source["workers"];
	        this.mode = source["mode"];
	    }
	}

}

